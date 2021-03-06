/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTTextView.h"

#import "RCTConvert.h"
#import "RCTEventDispatcher.h"
#import "RCTText.h"
#import "RCTUtils.h"
#import "UIView+React.h"

@interface RCTUITextView : UITextView

@property (nonatomic, assign) BOOL textWasPasted;

@end

@implementation RCTUITextView
{
  BOOL _jsRequestingFirstResponder;
}

- (void)paste:(id)sender
{
  _textWasPasted = YES;
  [super paste:sender];
}

- (void)reactWillMakeFirstResponder
{
  _jsRequestingFirstResponder = YES;
}

- (BOOL)canBecomeFirstResponder
{
  return _jsRequestingFirstResponder;
}

- (void)reactDidMakeFirstResponder
{
  _jsRequestingFirstResponder = NO;
}

@end

@implementation RCTTextView
{
  RCTEventDispatcher *_eventDispatcher;
  NSString *_placeholder;
  UITextView *_placeholderView;
  UITextView *_textView;
  NSInteger _nativeEventCount;
  RCTText *_richTextView;
  NSAttributedString *_pendingAttributedText;
  NSMutableArray<UIView *> *_subviews;
  BOOL _blockTextShouldChange;
  UITextRange *_previousSelectionRange;
  UIScrollView *_scrollView;
}

- (instancetype)initWithEventDispatcher:(RCTEventDispatcher *)eventDispatcher
{
  RCTAssertParam(eventDispatcher);

  if ((self = [super initWithFrame:CGRectZero])) {
    _contentInset = UIEdgeInsetsZero;
    _eventDispatcher = eventDispatcher;
    _placeholderTextColor = [self defaultPlaceholderTextColor];

    _textView = [[RCTUITextView alloc] initWithFrame:CGRectZero];
    _textView.backgroundColor = [UIColor clearColor];
    _textView.scrollsToTop = NO;
    _textView.scrollEnabled = NO;
    _textView.delegate = self;

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    [_scrollView addSubview:_textView];

    _previousSelectionRange = _textView.selectedTextRange;

    _subviews = [NSMutableArray new];
    [self addSubview:_scrollView];
  }
  return self;
}

RCT_NOT_IMPLEMENTED(- (instancetype)initWithFrame:(CGRect)frame)
RCT_NOT_IMPLEMENTED(- (instancetype)initWithCoder:(NSCoder *)aDecoder)

- (NSArray<UIView *> *)reactSubviews
{
  return _subviews;
}

- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)index
{
  if ([subview isKindOfClass:[RCTText class]]) {
    if (_richTextView) {
      RCTLogError(@"Tried to insert a second <Text> into <TextInput> - there can only be one.");
    }
    _richTextView = (RCTText *)subview;
    [_subviews insertObject:_richTextView atIndex:index];
  } else {
    [_subviews insertObject:subview atIndex:index];
    [self insertSubview:subview atIndex:index];
  }
}

- (void)removeReactSubview:(UIView *)subview
{
  if (_richTextView == subview) {
    [_subviews removeObject:_richTextView];
    _richTextView = nil;
  } else {
    [_subviews removeObject:subview];
    [subview removeFromSuperview];
  }
}

- (void)setMostRecentEventCount:(NSInteger)mostRecentEventCount
{
  _mostRecentEventCount = mostRecentEventCount;

  // Props are set after uiBlockToAmendWithShadowViewRegistry, which means that
  // at the time performTextUpdate is called, _mostRecentEventCount will be
  // behind _eventCount, with the result that performPendingTextUpdate will do
  // nothing. For that reason we call it again here after mostRecentEventCount
  // has been set.
  [self performPendingTextUpdate];
}

- (void)performTextUpdate
{
  if (_richTextView) {
    _pendingAttributedText = _richTextView.textStorage;
    [self performPendingTextUpdate];
  } else if (!self.text) {
    _textView.attributedText = nil;
  }
}

- (void)performPendingTextUpdate
{
  if (!_pendingAttributedText || _mostRecentEventCount < _nativeEventCount) {
    return;
  }

  if ([_textView.attributedText isEqualToAttributedString:_pendingAttributedText]) {
    _pendingAttributedText = nil; // Don't try again.
    return;
  }

  // When we update the attributed text, there might be pending autocorrections
  // that will get accepted by default. In order for this to not garble our text,
  // we temporarily block all textShouldChange events so they are not applied.
  _blockTextShouldChange = YES;

  NSRange range = _textView.selectedRange;
  _textView.attributedText = _pendingAttributedText;
  _pendingAttributedText = nil;
  _textView.selectedRange = range;
  [_textView layoutIfNeeded];

  [self _setPlaceholderVisibility];

  _blockTextShouldChange = NO;
}

- (void)updateFrames
{
  // Adjust the insets so that they are as close as possible to single-line
  // RCTTextField defaults, using the system defaults of font size 17 and a
  // height of 31 points.
  //
  // We apply the left inset to the frame since a negative left text-container
  // inset mysteriously causes the text to be hidden until the text view is
  // first focused.
  UIEdgeInsets adjustedFrameInset = UIEdgeInsetsZero;
  adjustedFrameInset.left = _contentInset.left - 5;

  UIEdgeInsets adjustedTextContainerInset = _contentInset;
  adjustedTextContainerInset.top += 5;
  adjustedTextContainerInset.left = 0;

  CGRect frame = UIEdgeInsetsInsetRect(self.bounds, adjustedFrameInset);
  _textView.frame = frame;
  _placeholderView.frame = frame;
  _scrollView.frame = frame;
  [self updateContentSize];

  _textView.textContainerInset = adjustedTextContainerInset;
  _placeholderView.textContainerInset = adjustedTextContainerInset;
}

- (void)updateContentSize
{
  _textView.scrollEnabled = YES;
  _scrollView.contentSize = _textView.contentSize;
  _textView.frame = (CGRect){CGPointZero, _scrollView.contentSize};
  _textView.scrollEnabled = NO;
}

- (void)updatePlaceholder
{
  [_placeholderView removeFromSuperview];
  _placeholderView = nil;

  if (_placeholder) {
    _placeholderView = [[UITextView alloc] initWithFrame:self.bounds];
    _placeholderView.editable = NO;
    _placeholderView.userInteractionEnabled = NO;
    _placeholderView.backgroundColor = [UIColor clearColor];
    _placeholderView.scrollEnabled = false;
    _placeholderView.scrollsToTop = NO;
    _placeholderView.attributedText =
    [[NSAttributedString alloc] initWithString:_placeholder attributes:@{
      NSFontAttributeName : (_textView.font ? _textView.font : [self defaultPlaceholderFont]),
      NSForegroundColorAttributeName : _placeholderTextColor
    }];

    [self insertSubview:_placeholderView belowSubview:_textView];
    [self _setPlaceholderVisibility];
  }
}

- (UIFont *)font
{
  return _textView.font;
}

- (void)setFont:(UIFont *)font
{
  _textView.font = font;
  [self updatePlaceholder];
}

- (void)setPlaceholder:(NSString *)placeholder
{
  _placeholder = placeholder;
  [self updatePlaceholder];
}

- (void)setPlaceholderTextColor:(UIColor *)placeholderTextColor
{
  if (placeholderTextColor) {
    _placeholderTextColor = placeholderTextColor;
  } else {
    _placeholderTextColor = [self defaultPlaceholderTextColor];
  }
  [self updatePlaceholder];
}

- (void)setContentInset:(UIEdgeInsets)contentInset
{
  _contentInset = contentInset;
  [self updateFrames];
}

- (NSString *)text
{
  return _textView.text;
}

- (BOOL)textView:(RCTUITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
  if (_blockTextShouldChange) {
    return NO;
  }

  if (textView.textWasPasted) {
    textView.textWasPasted = NO;
  } else {
    [_eventDispatcher sendTextEventWithType:RCTTextEventTypeKeyPress
                                   reactTag:self.reactTag
                                       text:nil
                                        key:text
                                 eventCount:_nativeEventCount];
  }

  if (_maxLength == nil) {
    return YES;
  }
  NSUInteger allowedLength = _maxLength.integerValue - textView.text.length + range.length;
  if (text.length > allowedLength) {
    if (text.length > 1) {
      // Truncate the input string so the result is exactly maxLength
      NSString *limitedString = [text substringToIndex:allowedLength];
      NSMutableString *newString = textView.text.mutableCopy;
      [newString replaceCharactersInRange:range withString:limitedString];
      textView.text = newString;
      // Collapse selection at end of insert to match normal paste behavior
      UITextPosition *insertEnd = [textView positionFromPosition:textView.beginningOfDocument
                                                          offset:(range.location + allowedLength)];
      textView.selectedTextRange = [textView textRangeFromPosition:insertEnd toPosition:insertEnd];
      [self textViewDidChange:textView];
    }
    return NO;
  } else {
    return YES;
  }
}

- (void)textViewDidChangeSelection:(RCTUITextView *)textView
{
  if (_onSelectionChange &&
      textView.selectedTextRange != _previousSelectionRange &&
      ![textView.selectedTextRange isEqual:_previousSelectionRange]) {

    _previousSelectionRange = textView.selectedTextRange;

    UITextRange *selection = textView.selectedTextRange;
    NSInteger start = [textView offsetFromPosition:[textView beginningOfDocument] toPosition:selection.start];
    NSInteger end = [textView offsetFromPosition:[textView beginningOfDocument] toPosition:selection.end];
    _onSelectionChange(@{
      @"selection": @{
        @"start": @(start),
        @"end": @(end),
      },
    });
  }
}

- (void)setText:(NSString *)text
{
  NSInteger eventLag = _nativeEventCount - _mostRecentEventCount;
  if (eventLag == 0 && ![text isEqualToString:_textView.text]) {
    UITextRange *selection = _textView.selectedTextRange;
    _textView.text = text;
    [self _setPlaceholderVisibility];
    _textView.selectedTextRange = selection; // maintain cursor position/selection - this is robust to out of bounds
  } else if (eventLag > RCTTextUpdateLagWarningThreshold) {
    RCTLogWarn(@"Native TextInput(%@) is %zd events ahead of JS - try to make your JS faster.", self.text, eventLag);
  }
}

- (void)_setPlaceholderVisibility
{
  if (_textView.text.length > 0) {
    [_placeholderView setHidden:YES];
  } else {
    [_placeholderView setHidden:NO];
  }
}

- (void)setAutoCorrect:(BOOL)autoCorrect
{
  _textView.autocorrectionType = (autoCorrect ? UITextAutocorrectionTypeYes : UITextAutocorrectionTypeNo);
}

- (BOOL)autoCorrect
{
  return _textView.autocorrectionType == UITextAutocorrectionTypeYes;
}

- (BOOL)textViewShouldBeginEditing:(UITextView *)textView
{
  if (_selectTextOnFocus) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [textView selectAll:nil];
    });
  }
  return YES;
}

- (void)textViewDidBeginEditing:(UITextView *)textView
{
  if (_clearTextOnFocus) {
    _textView.text = @"";
    [self _setPlaceholderVisibility];
  }

  [_eventDispatcher sendTextEventWithType:RCTTextEventTypeFocus
                                 reactTag:self.reactTag
                                     text:nil
                                      key:nil
                               eventCount:_nativeEventCount];
}

- (void)textViewDidChange:(UITextView *)textView
{
  [self updateContentSize];
  [self _setPlaceholderVisibility];
  _nativeEventCount++;
  [_eventDispatcher sendTextEventWithType:RCTTextEventTypeChange
                                 reactTag:self.reactTag
                                     text:textView.text
                                      key:nil
                               eventCount:_nativeEventCount];

}

- (void)textViewDidEndEditing:(UITextView *)textView
{
  [_eventDispatcher sendTextEventWithType:RCTTextEventTypeEnd
                                 reactTag:self.reactTag
                                     text:textView.text
                                      key:nil
                               eventCount:_nativeEventCount];

  [_eventDispatcher sendTextEventWithType:RCTTextEventTypeBlur
                                 reactTag:self.reactTag
                                     text:nil
                                      key:nil
                               eventCount:_nativeEventCount];
}

- (void)reactWillMakeFirstResponder
{
  [_textView reactWillMakeFirstResponder];
}

- (BOOL)becomeFirstResponder
{
  return [_textView becomeFirstResponder];
}

- (void)reactDidMakeFirstResponder
{
  [_textView reactDidMakeFirstResponder];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  [self updateFrames];
}

- (UIFont *)defaultPlaceholderFont
{
  return [UIFont systemFontOfSize:17];
}

- (UIColor *)defaultPlaceholderTextColor
{
  return [UIColor colorWithRed:0.0/255.0 green:0.0/255.0 blue:0.098/255.0 alpha:0.22];
}

@end
