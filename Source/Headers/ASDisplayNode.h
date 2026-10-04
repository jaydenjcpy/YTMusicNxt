// Minimal AsyncDisplayKit interfaces needed by the Return-YouTube-Music-Dislikes
// port. Trimmed from PoomSmart/YouTubeHeader; see YTILikeButtonRenderer.h for
// why these are hand-written rather than vendored.
//
// ASDisplayNode inherits from NSObject, so `view` and the Yoga accessors are
// declared here explicitly. ASCollectionView and _ASCollectionViewCell have no
// superclass inside the app binary because they subclass UIKit classes.

#import <UIKit/UIKit.h>

@interface ASDisplayNode : NSObject

@property (nonatomic, readonly) UIView *view;
@property (nonatomic, copy) NSString *accessibilityLabel;

- (UIViewController *)closestViewController;

@property (nonatomic, readonly) NSArray<ASDisplayNode *> *yogaChildren;
- (void)addYogaChild:(ASDisplayNode *)node;

@end

@interface ASCellNode : ASDisplayNode
@end

@interface ASControlNode : ASDisplayNode
@end

@interface ASTextNode : ASControlNode

@property (nonatomic, copy) NSAttributedString *attributedText;

@end

@interface ELMNodeController : NSObject
@end

@interface ELMTextNode : ASTextNode

@property (nonatomic, strong, readonly) ELMNodeController *controller;
@property (nonatomic, strong, readonly) id element;

@end

@interface ELMContainerNode : ASDisplayNode
@end

@interface ELMCellNode : ASCellNode

@property (nonatomic, strong, readonly) ELMNodeController *controller;

@end

@interface ELMNodeFactory : NSObject

+ (instancetype)sharedInstance;
- (id)nodeWithElement:(id)element materializationContext:(const void *)context;
- (Class)classForElement:(id)element materializationContext:(const void *)context;

@end

@interface _ASCollectionViewCell : UICollectionViewCell

@property (nonatomic, readonly) ASDisplayNode *node;

@end

@interface ASCollectionView : UICollectionView

- (ELMCellNode *)nodeForItemAtIndexPath:(NSIndexPath *)indexPath;

@end