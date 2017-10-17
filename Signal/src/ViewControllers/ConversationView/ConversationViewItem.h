//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewLayout.h"
#import "OWSAudioAttachmentPlayer.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OWSMessageCellType) {
    OWSMessageCellType_TextMessage,
    OWSMessageCellType_OversizeTextMessage,
    OWSMessageCellType_StillImage,
    OWSMessageCellType_AnimatedImage,
    OWSMessageCellType_Audio,
    OWSMessageCellType_Video,
    OWSMessageCellType_GenericAttachment,
    OWSMessageCellType_DownloadingAttachment,
    // Treat invalid messages as empty text messages.
    OWSMessageCellType_Unknown = OWSMessageCellType_TextMessage,
};

NSString *NSStringForOWSMessageCellType(OWSMessageCellType cellType);

@class ConversationViewCell;
@class OWSAudioMessageView;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSInteraction;

// This is a ViewModel for cells in the conversation view.
//
// The lifetime of this class is the lifetime of that cell
// in the load window of the conversation view.
//
// Critically, this class implements ConversationViewLayoutItem
// and does caching of the cell's size.
@interface ConversationViewItem : NSObject <ConversationViewLayoutItem, OWSAudioAttachmentPlayerDelegate>

@property (nonatomic, readonly) TSInteraction *interaction;

@property (nonatomic, readonly) BOOL isGroupThread;

@property (nonatomic) BOOL shouldShowDate;
@property (nonatomic) BOOL shouldHideRecipientStatus;

@property (nonatomic) NSInteger row;
@property (nonatomic) NSInteger lastRow;

//@property (nonatomic, weak) ConversationViewCell *lastCell;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithTSInteraction:(TSInteraction *)interaction isGroupThread:(BOOL)isGroupThread;

- (ConversationViewCell *)dequeueCellForCollectionView:(UICollectionView *)collectionView
                                             indexPath:(NSIndexPath *)indexPath;

- (void)replaceInteraction:(TSInteraction *)interaction;

- (void)clearCachedLayoutState;

#pragma mark - Audio Playback

@property (nonatomic, weak) OWSAudioMessageView *lastAudioMessageView;

@property (nonatomic, nullable) NSNumber *audioDurationSeconds;

- (CGFloat)audioProgressSeconds;

#pragma mark - Expiration

// TODO:
//@property (nonatomic, readonly) BOOL isExpiringMessage;
//@property (nonatomic, readonly) BOOL shouldStartExpireTimer;
//@property (nonatomic, readonly) double expiresAtSeconds;
//@property (nonatomic, readonly) uint32_t expiresInSeconds;

#pragma mark - View State Caching

// These methods only apply to text & attachment messages.
- (OWSMessageCellType)messageCellType;
- (nullable NSString *)textMessage;
- (nullable TSAttachmentStream *)attachmentStream;
- (nullable TSAttachmentPointer *)attachmentPointer;
- (CGSize)contentSize;

// A generic property that cells can use to cache their loaded
// media.  This cache is volatile and will get evacuated based
// on scroll state, so that we only retain state for a sliding
// window of cells that are almost on-screen.
@property (nonatomic, nullable) id cachedCellMedia;
@property (nonatomic) BOOL didCellMediaFailToLoad;

// TODO:
//// Cells will request that this adapter clear its cached media views,
//// but the adapter should only honor requests from the last cell to
//// use its views.
//- (void)setLastPresentingCell:(nullable id)cell;
//- (void)clearCachedMediaViewsIfLastPresentingCell:(id)cell;

#pragma mark - UIMenuController

- (NSArray<UIMenuItem *> *)menuControllerItems;
- (BOOL)canPerformAction:(SEL)action;
- (void)copyAction;
- (void)shareAction;
- (void)saveAction;
- (void)deleteAction;
- (SEL)metadataActionSelector;

@end

NS_ASSUME_NONNULL_END
