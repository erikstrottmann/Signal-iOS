//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationViewCell;
@class ConversationViewItem;
@class OWSContactOffersInteraction;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSInteraction;
@class TSMessage;
@class TSOutgoingMessage;

@protocol ConversationViewCellDelegate <NSObject>

- (void)didTapImageViewItem:(ConversationViewItem *)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIView *)imageView;
- (void)didTapVideoViewItem:(ConversationViewItem *)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream;
- (void)didTapAudioViewItem:(ConversationViewItem *)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream;
- (void)didTapOversizeTextMessage:(NSString *)displayableText attachmentStream:(TSAttachmentStream *)attachmentStream;
- (void)didTapFailedIncomingAttachment:(ConversationViewItem *)viewItem
                     attachmentPointer:(TSAttachmentPointer *)attachmentPointer;
- (void)didTapFailedOutgoingMessage:(TSOutgoingMessage *)message;

- (void)showMetadataViewForMessage:(TSMessage *)message;

#pragma mark - System Cell

// TODO: We might want to decompose this method.
- (void)didTapSystemMessageWithInteraction:(TSInteraction *)interaction;

#pragma mark - Offers

- (void)tappedUnknownContactBlockOfferMessage:(OWSContactOffersInteraction *)interaction;
- (void)tappedAddToContactsOfferMessage:(OWSContactOffersInteraction *)interaction;
- (void)tappedAddToProfileWhitelistOfferMessage:(OWSContactOffersInteraction *)interaction;

#pragma mark - Formatting

- (NSAttributedString *)attributedContactOrProfileNameForPhoneIdentifier:(NSString *)recipientId;

@end

#pragma mark -

// TODO: Consider making this a protocol.
@interface ConversationViewCell : UICollectionViewCell

@property (nonatomic, nullable, weak) id<ConversationViewCellDelegate> delegate;

@property (nonatomic, nullable) ConversationViewItem *viewItem;

@property (nonatomic) BOOL isCellVisible;

- (void)loadForDisplay:(int)contentWidth;

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth;

@end

NS_ASSUME_NONNULL_END
