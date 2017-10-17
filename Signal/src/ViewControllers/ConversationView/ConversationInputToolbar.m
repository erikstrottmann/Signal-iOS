//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationInputToolbar.h"
#import "ConversationInputTextView.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <SignalServiceKit/NSTimer+OWS.h>

NS_ASSUME_NONNULL_BEGIN

static void *kConversationInputTextViewObservingContext = &kConversationInputTextViewObservingContext;

@interface ConversationInputToolbar () <UIGestureRecognizerDelegate, UITextViewDelegate>

@property (nonatomic) ConversationInputTextView *inputTextView;
@property (nonatomic) UIButton *attachmentButton;
@property (nonatomic) UIButton *sendButton;
@property (nonatomic) BOOL shouldShowVoiceMemoButton;
@property (nonatomic) UIButton *voiceMemoButton;
@property (nonatomic) UIView *leadingButtonWrapper;
@property (nonatomic) UIView *trailingButtonWrapper;

@property (nonatomic) NSArray<NSLayoutConstraint *> *contentContraints;

#pragma mark - Voice Memo Recording UI

@property (nonatomic, nullable) UIView *voiceMemoUI;
@property (nonatomic) UIView *voiceMemoContentView;
@property (nonatomic) NSDate *voiceMemoStartTime;
@property (nonatomic, nullable) NSTimer *voiceMemoUpdateTimer;
@property (nonatomic) UILabel *recordingLabel;
@property (nonatomic) BOOL isRecordingVoiceMemo;
@property (nonatomic) CGPoint voiceMemoGestureStartLocation;

@end

#pragma mark -

@implementation ConversationInputToolbar

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self createContents];
    }

    return self;
}

- (void)dealloc
{
    [self removeKVOObservers];
}

- (void)createContents
{
    self.layoutMargins = UIEdgeInsetsZero;

    // TODO: I think there's an easier to get the right appearance,
    // but I can't figure it out.
    UIView *backgroundView = [UIView new];
    backgroundView.backgroundColor = [UIColor colorWithWhite:249 / 255.f alpha:1.f];
    [self addSubview:backgroundView];
    [backgroundView autoPinEdgesToSuperviewEdges];

    _inputTextView = [ConversationInputTextView new];
    self.inputTextView.delegate = self;
    [self addSubview:self.inputTextView];

    // We want to be permissive about taps on the send and attachment buttons,
    // so we use wrapper views that capture nearby taps.  This is a lot easier
    // than trying to manipulate the size of the buttons themselves, as you
    // can't coordinate the layout of the button content (e.g. image or text)
    // using iOS auto layout.
    _leadingButtonWrapper = [UIView containerView];
    [self.leadingButtonWrapper
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(leadingButtonTapped:)]];
    [self addSubview:self.leadingButtonWrapper];
    _trailingButtonWrapper = [UIView containerView];
    [self.trailingButtonWrapper
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(trailingButtonTapped:)]];
    [self addSubview:self.trailingButtonWrapper];

    _attachmentButton = [[UIButton alloc] init];
    self.attachmentButton.accessibilityLabel
        = NSLocalizedString(@"ATTACHMENT_LABEL", @"Accessibility label for attaching photos");
    self.attachmentButton.accessibilityHint = NSLocalizedString(
        @"ATTACHMENT_HINT", @"Accessibility hint describing what you can do with the attachment button");
    [self.attachmentButton addTarget:self
                              action:@selector(attachmentButtonPressed)
                    forControlEvents:UIControlEventTouchUpInside];
    [self.attachmentButton setImage:[UIImage imageNamed:@"btnAttachments--blue"] forState:UIControlStateNormal];
    [self.leadingButtonWrapper addSubview:self.attachmentButton];

    // TODO: Fix layout in this class.
    _sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.sendButton
        setTitle:NSLocalizedString(@"SEND_BUTTON_TITLE", @"Label for the send button in the conversation view.")
        forState:UIControlStateNormal];
    [self.sendButton setTitleColor:[UIColor ows_materialBlueColor] forState:UIControlStateNormal];
    self.sendButton.titleLabel.font = [UIFont ows_regularFontWithSize:17.0f];
    self.sendButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.sendButton.titleLabel.font = [UIFont ows_mediumFontWithSize:16.f];
    [self.sendButton addTarget:self action:@selector(sendButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.trailingButtonWrapper addSubview:self.sendButton];

    UIImage *voiceMemoIcon = [UIImage imageNamed:@"voice-memo-button"];
    OWSAssert(voiceMemoIcon);
    self.voiceMemoButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.voiceMemoButton setImage:[voiceMemoIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                          forState:UIControlStateNormal];
    self.voiceMemoButton.imageView.tintColor = [UIColor ows_materialBlueColor];
    [self.trailingButtonWrapper addSubview:self.voiceMemoButton];

    // We want to be permissive about the voice message gesture, so we hang
    // the long press GR on the button's wrapper, not the button itself.
    UILongPressGestureRecognizer *longPressGestureRecognizer =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPressGestureRecognizer.minimumPressDuration = 0;
    longPressGestureRecognizer.delegate = self;
    [self.trailingButtonWrapper addGestureRecognizer:longPressGestureRecognizer];

    self.userInteractionEnabled = YES;

    [self addKVOObservers];

    [self ensureShouldShowVoiceMemoButton];

    [self ensureContentConstraints];
}

- (void)setInputTextViewDelegate:(id<ConversationInputTextViewDelegate>)value
{
    OWSAssert(self.inputTextView);
    OWSAssert(value);

    self.inputTextView.inputTextViewDelegate = value;
}

- (NSString *)messageText
{
    OWSAssert(self.inputTextView);

    return self.inputTextView.trimmedText;
}

- (void)setMessageText:(NSString *_Nullable)value
{
    OWSAssert(self.inputTextView);

    self.inputTextView.text = value;

    [self ensureShouldShowVoiceMemoButton];
    // TODO: Remove this when we remove the delegate method.
    [self textViewDidChange:self.inputTextView];
}

- (void)clearTextMessage
{
    [self setMessageText:nil];
    [self.inputTextView.undoManager removeAllActions];
}

- (void)setShouldShowVoiceMemoButton:(BOOL)shouldShowVoiceMemoButton
{
    if (_shouldShowVoiceMemoButton == shouldShowVoiceMemoButton) {
        return;
    }

    _shouldShowVoiceMemoButton = shouldShowVoiceMemoButton;

    [self ensureContentConstraints];
}

- (void)beginEditingTextMessage
{
    [self.inputTextView becomeFirstResponder];
}

- (void)endEditingTextMessage
{
    [self.inputTextView resignFirstResponder];
}

- (void)ensureContentConstraints
{
    [NSLayoutConstraint deactivateConstraints:self.contentContraints];

    const int textViewVInset = 5;
    const int contentHInset = 6;
    const int contentHSpacing = 6;

    // We want to grow the text input area to fit its content within reason.
    const CGFloat kMinTextViewHeight = ceil(self.inputTextView.font.lineHeight
        + self.inputTextView.textContainerInset.top + self.inputTextView.textContainerInset.bottom
        + self.inputTextView.contentInset.top + self.inputTextView.contentInset.bottom);
    const CGFloat kMaxTextViewHeight = 100.f;
    const CGFloat textViewDesiredHeight = (self.inputTextView.contentSize.height + self.inputTextView.contentInset.top
        + self.inputTextView.contentInset.bottom);
    const CGFloat textViewHeight = ceil(MAX(kMinTextViewHeight, MIN(kMaxTextViewHeight, textViewDesiredHeight)));
    const CGFloat kMinContentHeight = kMinTextViewHeight + textViewVInset * 2;

    UIButton *leadingButton = self.attachmentButton;
    UIButton *trailingButton = (self.shouldShowVoiceMemoButton ? self.voiceMemoButton : self.sendButton);
    UIButton *inactiveTrailingButton = (self.shouldShowVoiceMemoButton ? self.sendButton : self.voiceMemoButton);
    leadingButton.enabled = YES;
    trailingButton.enabled = YES;
    inactiveTrailingButton.enabled = NO;
    leadingButton.hidden = NO;
    trailingButton.hidden = NO;
    inactiveTrailingButton.hidden = YES;

    [leadingButton setContentHuggingHigh];
    [trailingButton setContentHuggingHigh];
    [leadingButton setCompressionResistanceHigh];
    [trailingButton setCompressionResistanceHigh];
    [self.inputTextView setContentHuggingLow];

    OWSAssert(leadingButton.superview == self.leadingButtonWrapper);
    OWSAssert(trailingButton.superview == self.trailingButtonWrapper);

    // The leading and trailing buttons should be center-aligned with the
    // inputTextView when the inputTextView is at its minimum size.
    //
    // We want the leading and trailing buttons to hug the bottom of the input
    // toolbar as the inputTextView expands.
    //
    // Therefore we fix the button heights to the size of the toolbar when
    // inputTextView is at its minimum size.
    //
    // Additionally, we use "wrapper" views around the leading and trailing
    // buttons to expand their hot area.
    self.contentContraints = @[
        [self.leadingButtonWrapper autoPinLeadingToSuperview],
        [self.leadingButtonWrapper autoPinEdgeToSuperviewEdge:ALEdgeTop],
        [self.leadingButtonWrapper autoPinEdgeToSuperviewEdge:ALEdgeBottom],

        [leadingButton autoSetDimension:ALDimensionHeight toSize:kMinContentHeight],
        [leadingButton autoPinLeadingToSuperviewWithMargin:contentHInset],
        [leadingButton autoPinTrailingToSuperviewWithMargin:contentHSpacing],
        [leadingButton autoPinEdgeToSuperviewEdge:ALEdgeBottom],

        [self.inputTextView autoPinLeadingToTrailingOfView:self.leadingButtonWrapper],
        [self.inputTextView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:textViewVInset],
        [self.inputTextView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:textViewVInset],
        [self.inputTextView autoSetDimension:ALDimensionHeight toSize:textViewHeight],

        [self.trailingButtonWrapper autoPinLeadingToTrailingOfView:self.inputTextView],
        [self.trailingButtonWrapper autoPinTrailingToSuperview],
        [self.trailingButtonWrapper autoPinEdgeToSuperviewEdge:ALEdgeTop],
        [self.trailingButtonWrapper autoPinEdgeToSuperviewEdge:ALEdgeBottom],

        [trailingButton autoSetDimension:ALDimensionHeight toSize:kMinContentHeight],
        [trailingButton autoPinLeadingToSuperviewWithMargin:contentHSpacing],
        [trailingButton autoPinTrailingToSuperviewWithMargin:contentHInset],
        [trailingButton autoPinEdgeToSuperviewEdge:ALEdgeBottom],
    ];

    [self layoutIfNeeded];
}

- (void)ensureShouldShowVoiceMemoButton
{
    self.shouldShowVoiceMemoButton = self.inputTextView.trimmedText.length < 1;
}

- (void)handleLongPress:(UIGestureRecognizer *)sender
{
    if (!self.shouldShowVoiceMemoButton) {
        return;
    }

    switch (sender.state) {
        case UIGestureRecognizerStatePossible:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            if (self.isRecordingVoiceMemo) {
                // Cancel voice message if necessary.
                self.isRecordingVoiceMemo = NO;
                [self.inputToolbarDelegate voiceMemoGestureDidCancel];
            }
            break;
        case UIGestureRecognizerStateBegan:
            if (self.isRecordingVoiceMemo) {
                // Cancel voice message if necessary.
                self.isRecordingVoiceMemo = NO;
                [self.inputToolbarDelegate voiceMemoGestureDidCancel];
            }
            // Start voice message.
            self.isRecordingVoiceMemo = YES;
            self.voiceMemoGestureStartLocation = [sender locationInView:self];
            [self.inputToolbarDelegate voiceMemoGestureDidStart];
            break;
        case UIGestureRecognizerStateChanged:
            if (self.isRecordingVoiceMemo) {
                // Check for "slide to cancel" gesture.
                CGPoint location = [sender locationInView:self];
                // For LTR/RTL, swiping in either direction will cancel.
                // This is okay because there's only space on screen to perform the
                // gesture in one direction.
                CGFloat offset = fabs(self.voiceMemoGestureStartLocation.x - location.x);
                // The lower this value, the easier it is to cancel by accident.
                // The higher this value, the harder it is to cancel.
                const CGFloat kCancelOffsetPoints = 100.f;
                CGFloat cancelAlpha = offset / kCancelOffsetPoints;
                BOOL isCancelled = cancelAlpha >= 1.f;
                if (isCancelled) {
                    self.isRecordingVoiceMemo = NO;
                    [self.inputToolbarDelegate voiceMemoGestureDidCancel];
                } else {
                    [self.inputToolbarDelegate voiceMemoGestureDidChange:cancelAlpha];
                }
            }
            break;
        case UIGestureRecognizerStateEnded:
            if (self.isRecordingVoiceMemo) {
                // End voice message.
                self.isRecordingVoiceMemo = NO;
                [self.inputToolbarDelegate voiceMemoGestureDidEnd];
            }
            break;
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if ([gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return self.shouldShowVoiceMemoButton;
    } else {
        return YES;
    }
}

#pragma mark - Voice Memo

- (void)showVoiceMemoUI
{
    OWSAssert([NSThread isMainThread]);

    self.voiceMemoStartTime = [NSDate date];

    [self.voiceMemoUI removeFromSuperview];

    self.voiceMemoUI = [UIView new];
    self.voiceMemoUI.userInteractionEnabled = NO;
    self.voiceMemoUI.backgroundColor = [UIColor whiteColor];
    [self addSubview:self.voiceMemoUI];
    self.voiceMemoUI.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);

    self.voiceMemoContentView = [UIView new];
    [self.voiceMemoUI addSubview:self.voiceMemoContentView];
    [self.voiceMemoContentView autoPinToSuperviewEdges];

    self.recordingLabel = [UILabel new];
    self.recordingLabel.textColor = [UIColor ows_destructiveRedColor];
    self.recordingLabel.font = [UIFont ows_mediumFontWithSize:14.f];
    [self.voiceMemoContentView addSubview:self.recordingLabel];
    [self updateVoiceMemo];

    UIImage *icon = [UIImage imageNamed:@"voice-memo-button"];
    OWSAssert(icon);
    UIImageView *imageView =
        [[UIImageView alloc] initWithImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    imageView.tintColor = [UIColor ows_destructiveRedColor];
    [self.voiceMemoContentView addSubview:imageView];

    NSMutableAttributedString *cancelString = [NSMutableAttributedString new];
    const CGFloat cancelArrowFontSize = ScaleFromIPhone5To7Plus(18.4, 20.f);
    const CGFloat cancelFontSize = ScaleFromIPhone5To7Plus(14.f, 16.f);
    NSString *arrowHead = (self.isRTL ? @"\uf105" : @"\uf104");
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:arrowHead
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                                           NSForegroundColorAttributeName : [UIColor ows_destructiveRedColor],
                                           NSBaselineOffsetAttributeName : @(-1.f),
                                       }]];
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:@"  "
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                                           NSForegroundColorAttributeName : [UIColor ows_destructiveRedColor],
                                           NSBaselineOffsetAttributeName : @(-1.f),
                                       }]];
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:NSLocalizedString(@"VOICE_MESSAGE_CANCEL_INSTRUCTIONS",
                                                      @"Indicates how to cancel a voice message.")
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_mediumFontWithSize:cancelFontSize],
                                           NSForegroundColorAttributeName : [UIColor ows_destructiveRedColor],
                                       }]];
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:@"  "
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                                           NSForegroundColorAttributeName : [UIColor ows_destructiveRedColor],
                                           NSBaselineOffsetAttributeName : @(-1.f),
                                       }]];
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:arrowHead
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                                           NSForegroundColorAttributeName : [UIColor ows_destructiveRedColor],
                                           NSBaselineOffsetAttributeName : @(-1.f),
                                       }]];
    UILabel *cancelLabel = [UILabel new];
    cancelLabel.attributedText = cancelString;
    [self.voiceMemoContentView addSubview:cancelLabel];

    const CGFloat kRedCircleSize = 100.f;
    UIView *redCircleView = [UIView new];
    redCircleView.backgroundColor = [UIColor ows_destructiveRedColor];
    redCircleView.layer.cornerRadius = kRedCircleSize * 0.5f;
    [redCircleView autoSetDimension:ALDimensionWidth toSize:kRedCircleSize];
    [redCircleView autoSetDimension:ALDimensionHeight toSize:kRedCircleSize];
    [self.voiceMemoContentView addSubview:redCircleView];
    [redCircleView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.voiceMemoButton];
    [redCircleView autoAlignAxis:ALAxisVertical toSameAxisOfView:self.voiceMemoButton];

    UIImage *whiteIcon = [UIImage imageNamed:@"voice-message-large-white"];
    OWSAssert(whiteIcon);
    UIImageView *whiteIconView = [[UIImageView alloc] initWithImage:whiteIcon];
    [redCircleView addSubview:whiteIconView];
    [whiteIconView autoCenterInSuperview];

    [imageView autoVCenterInSuperview];
    [imageView autoPinLeadingToSuperviewWithMargin:10.f];
    [self.recordingLabel autoVCenterInSuperview];
    [self.recordingLabel autoPinLeadingToTrailingOfView:imageView margin:5.f];
    [cancelLabel autoVCenterInSuperview];
    [cancelLabel autoHCenterInSuperview];
    [self.voiceMemoUI setNeedsLayout];
    [self.voiceMemoUI layoutSubviews];

    // Slide in the "slide to cancel" label.
    CGRect cancelLabelStartFrame = cancelLabel.frame;
    CGRect cancelLabelEndFrame = cancelLabel.frame;
    cancelLabelStartFrame.origin.x
        = (self.isRTL ? -self.voiceMemoUI.bounds.size.width : self.voiceMemoUI.bounds.size.width);
    cancelLabel.frame = cancelLabelStartFrame;
    [UIView animateWithDuration:0.35f
                          delay:0.f
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         cancelLabel.frame = cancelLabelEndFrame;
                     }
                     completion:nil];

    // Pulse the icon.
    imageView.layer.opacity = 1.f;
    [UIView animateWithDuration:0.5f
                          delay:0.2f
                        options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse
                        | UIViewAnimationOptionCurveEaseIn
                     animations:^{
                         imageView.layer.opacity = 0.f;
                     }
                     completion:nil];

    // Fade in the view.
    self.voiceMemoUI.layer.opacity = 0.f;
    [UIView animateWithDuration:0.2f
        animations:^{
            self.voiceMemoUI.layer.opacity = 1.f;
        }
        completion:^(BOOL finished) {
            if (finished) {
                self.voiceMemoUI.layer.opacity = 1.f;
            }
        }];

    [self.voiceMemoUpdateTimer invalidate];
    self.voiceMemoUpdateTimer = [NSTimer weakScheduledTimerWithTimeInterval:0.1f
                                                                     target:self
                                                                   selector:@selector(updateVoiceMemo)
                                                                   userInfo:nil
                                                                    repeats:YES];
}

- (void)hideVoiceMemoUI:(BOOL)animated
{
    OWSAssert([NSThread isMainThread]);

    UIView *oldVoiceMemoUI = self.voiceMemoUI;
    self.voiceMemoUI = nil;
    NSTimer *voiceMemoUpdateTimer = self.voiceMemoUpdateTimer;
    self.voiceMemoUpdateTimer = nil;

    [oldVoiceMemoUI.layer removeAllAnimations];

    if (animated) {
        [UIView animateWithDuration:0.35f
            animations:^{
                oldVoiceMemoUI.layer.opacity = 0.f;
            }
            completion:^(BOOL finished) {
                [oldVoiceMemoUI removeFromSuperview];
                [voiceMemoUpdateTimer invalidate];
            }];
    } else {
        [oldVoiceMemoUI removeFromSuperview];
        [voiceMemoUpdateTimer invalidate];
    }
}

- (void)setVoiceMemoUICancelAlpha:(CGFloat)cancelAlpha
{
    OWSAssert([NSThread isMainThread]);

    // Fade out the voice message views as the cancel gesture
    // proceeds as feedback.
    self.voiceMemoContentView.layer.opacity = MAX(0.f, MIN(1.f, 1.f - (float)cancelAlpha));
}

- (void)updateVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

    NSTimeInterval durationSeconds = fabs([self.voiceMemoStartTime timeIntervalSinceNow]);
    self.recordingLabel.text = [ViewControllerUtils formatDurationSeconds:(long)round(durationSeconds)];
    [self.recordingLabel sizeToFit];
}

- (void)cancelVoiceMemoIfNecessary
{
    if (self.isRecordingVoiceMemo) {
        self.isRecordingVoiceMemo = NO;
    }
}

#pragma mark - Event Handlers

- (void)leadingButtonTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self attachmentButtonPressed];
    }
}

- (void)trailingButtonTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        if (!self.shouldShowVoiceMemoButton) {
            [self sendButtonPressed];
        }
    }
}

- (void)sendButtonPressed
{
    OWSAssert(self.inputToolbarDelegate);

    [self.inputToolbarDelegate sendButtonPressed];
}

- (void)attachmentButtonPressed
{
    OWSAssert(self.inputToolbarDelegate);

    [self.inputToolbarDelegate attachmentButtonPressed];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    OWSAssert(textView == self.inputTextView);

    [textView becomeFirstResponder];
}

- (void)textViewDidChange:(UITextView *)textView
{
    OWSAssert(self.inputToolbarDelegate);
    OWSAssert(textView == self.inputTextView);

    [self ensureShouldShowVoiceMemoButton];
    [self.inputToolbarDelegate textViewDidChange];
}

- (void)textViewDidEndEditing:(UITextView *)textView
{
    OWSAssert(textView == self.inputTextView);

    [textView resignFirstResponder];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if (range.length > 0) {
        return YES;
    }
    if ([text isEqualToString:@"\n"]) {
        [self sendButtonPressed];
        return NO;
    }
    return YES;
}

#pragma mark - Text Input Sizing

- (void)addKVOObservers
{
    [self.inputTextView addObserver:self
                         forKeyPath:NSStringFromSelector(@selector(contentSize))
                            options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
                            context:kConversationInputTextViewObservingContext];
}

- (void)removeKVOObservers
{
    @try {
        [self.inputTextView removeObserver:self
                                forKeyPath:NSStringFromSelector(@selector(contentSize))
                                   context:kConversationInputTextViewObservingContext];
    } @catch (NSException *__unused exception) {
    }
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath
                      ofObject:(nullable id)object
                        change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(nullable void *)context
{
    if (context == kConversationInputTextViewObservingContext) {

        if (object == self.inputTextView && [keyPath isEqualToString:NSStringFromSelector(@selector(contentSize))]) {

            [self ensureContentConstraints];
        }
    }
}

@end

NS_ASSUME_NONNULL_END
