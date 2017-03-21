//
//  UITableViewCell+KVO.h
//  DYPwdDemo
//
//  Created by Ethank on 2017/3/20.
//  Copyright © 2017年 DY. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef void(^DYObservingBlock)(id observerObject, NSString *observerKey, id oldValue, id newValue);

@interface NSObject (KVO)

- (void)dy_addObserVer:(NSObject *)observer forKeyPath:(NSString *)keyPath withBlock:(DYObservingBlock)observeingBlock;

- (void)dy_removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath;

@end
