//
//  UITableViewCell+KVO.m
//  DYPwdDemo
//
//  Created by Ethank on 2017/3/20.
//  Copyright © 2017年 DY. All rights reserved.
//

#import "NSObject+KVO.h"

#import <objc/runtime.h>
#import <objc/message.h>

NSString *const DYKVOClassPrefix = @"DYKVOClassPrefix_";
NSString *const DYKVOAssociatedObservers = @"DYKVOAssociatedObservers";


#pragma mark - PGObservationInfo


@interface DYObservationInfo :NSObject

@property (nonatomic, weak) NSObject *observer;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) DYObservingBlock block;

@end

@implementation DYObservationInfo

- (instancetype)initWithObserver:(NSObject *)observer Key:(NSString *)key block:(DYObservingBlock)block
{
    self = [super init];
    if (self) {
        _observer = observer;
        _key = key;
        _block = block;
    }
    return self;
}

@end


#pragma mark - Debug Help Methods
static NSArray *ClassMethodNames(Class c)
{
    NSMutableArray *array = [NSMutableArray array];
    
    unsigned int methodCount = 0;
    Method *methodList = class_copyMethodList(c, &methodCount);
    unsigned int i;
    for(i = 0; i < methodCount; i++) {
        [array addObject: NSStringFromSelector(method_getName(methodList[i]))];
    }
    free(methodList);
    
    return array;
}


static void PrintDescription(NSString *name, id obj)
{
    NSString *str = [NSString stringWithFormat:
                     @"%@: %@\n\tNSObject class %s\n\tRuntime class %s\n\timplements methods <%@>\n\n",
                     name,
                     obj,
                     class_getName([obj class]),
                     class_getName(object_getClass(obj)),
                     [ClassMethodNames(object_getClass(obj)) componentsJoinedByString:@", "]];
    printf("%s\n", [str UTF8String]);
}


#pragma mark - Helpers
static NSString * getterForSetter(NSString *setter)
{
    if (setter.length <=0 || ![setter hasPrefix:@"set"] || ![setter hasSuffix:@":"]) {
        return nil;
    }
    
    // remove 'set' at the begining and ':' at the end
    NSRange range = NSMakeRange(3, setter.length - 4);
    NSString *key = [setter substringWithRange:range];
    
    // lower case the first letter
    NSString *firstLetter = [[key substringToIndex:1] lowercaseString];
    key = [key stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                       withString:firstLetter];
    
    return key;
}


static NSString * setterForGetter(NSString *getter)
{
    if (getter.length <= 0) {
        return nil;
    }
    
    // upper case the first letter
    NSString *firstLetter = [[getter substringToIndex:1] uppercaseString];
    NSString *remainingLetters = [getter substringFromIndex:1];
    
    // add 'set' at the begining and ':' at the end
    NSString *setter = [NSString stringWithFormat:@"set%@%@:", firstLetter, remainingLetters];
    
    return setter;
}


#pragma mark - Overridden Methods
static void kvo_setter(id self, SEL _cmd, id newValue)
{
    NSString *setterName = NSStringFromSelector(_cmd);
    NSString *getterName = getterForSetter(setterName);
    
    if (!getterName) {//没有实现setter
        NSString *reason = [NSString stringWithFormat:@"object of %@ does not have a set method", NSStringFromClass([self class])];
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:reason userInfo:nil];
        return ;
    }
    
    id oldvalue = [self valueForKey:getterName];
    
    struct objc_super supperClass = {
        .receiver = self,
        .super_class = class_getSuperclass((object_getClass(self)))
    };
    //为kvo类定义向super发送消息的方法
    void (*objc_msgSendSuper_auto)(id, SEL, id) = (void *)objc_msgSendSuper;
    //在kvo的setter方法中重写super的setter方法
    objc_msgSendSuper_auto((__bridge id)(&supperClass), _cmd, newValue);
    //遍历所有观察的属性找到对应的观察属性，调用block实现检测属性值改变
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge void *)DYKVOAssociatedObservers);
    for (DYObservationInfo *info in observers) {
        if ([info.key isEqualToString:getterName]) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                info.block(self, getterName, oldvalue, newValue);//调用block
            });
        }
    }
}


static Class kvo_class(id self, SEL _cmd)
{
    return class_getSuperclass(object_getClass(self));
}

#pragma mark - KVO Category

@implementation NSObject (KVO)

- (void)dy_addObserVer:(NSObject *)observer forKeyPath:(NSString *)keyPath withBlock:(DYObservingBlock)observeingBlock {
    //step1
    SEL setterSelector = NSSelectorFromString(setterForGetter(keyPath));
    
    Method setterMethod = class_getInstanceMethod([self class], setterSelector);
    if (!setterMethod) {// setter not imp
        NSString *reason = [NSString stringWithFormat:@"object %@ does not have a setter for %@", self, keyPath];
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:reason userInfo:nil];
        return;
    }
    
    Class classZ = object_getClass(self);//获取当前类
    NSString * className = NSStringFromClass(classZ);//获取当前类名
    if (![className hasPrefix:DYKVOClassPrefix]) {//kvo class not
        classZ = [self makeKVOClassWithOrignalClassName:className];//创建kvo类
        object_setClass(self, classZ);//交换当前类与kvo类的指向
    }//此后self 不在指向原类而是指向kvo类
    
    if (![self hasSelector:setterSelector]) {//如果kvo类没有实现（重写原类的）setter方法
        //获取原类setter方法的参数和返回值
        const char * types = method_getTypeEncoding(setterMethod);
        //为kvo类添加setter方法
        class_addMethod(classZ, setterSelector, (IMP)kvo_setter, types);
    }
    
    DYObservationInfo *info = [[DYObservationInfo alloc] initWithObserver:observer Key:keyPath block:observeingBlock];
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)DYKVOAssociatedObservers);
    if (!observers) {
        observers = [NSMutableArray array];
        objc_setAssociatedObject(self, (__bridge const void *)(DYKVOAssociatedObservers), observers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [observers addObject:info];
}

- (void)dy_removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath {
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge void *)DYKVOAssociatedObservers);
    DYObservationInfo *needRemoveObserver = nil;
    for (DYObservationInfo *info in observers) {
        if (info.observer == observer && [info.key isEqualToString:keyPath]) {
            needRemoveObserver = info;
            break;
        }
    }
    [observers removeObject:needRemoveObserver];
}

#pragma mark- create kvo class

- (Class)makeKVOClassWithOrignalClassName:(NSString *)orignalName {
    
    NSString *kvoClassName = [DYKVOClassPrefix stringByAppendingString:orignalName];
    Class kvoClass = NSClassFromString(kvoClassName);
    if (kvoClass) {
        return kvoClass;
    }
    
    //if kvoClass does not exist
    
    //获取原类
    Class orignalClass = object_getClass(self);//
    /*
     *  第一个参数 作为新类的supperclass
     *  第二个参数 作为新类的名字
     *  第三个参数通常为 0
     */
    Class newKvoClass = objc_allocateClassPair(orignalClass, kvoClassName.UTF8String, 0);
    //获取原类的方法
    Method orignalClassMethod = class_getInstanceMethod(orignalClass, @selector(class));
    const char * types = method_getTypeEncoding(orignalClassMethod);
    //为新类添加同样的方法
    class_addMethod(newKvoClass, @selector(class), (IMP)kvo_class, types);
    //为newKvoClass 注册class方法
    objc_registerClassPair(newKvoClass);
    
    return newKvoClass;
}

- (BOOL)hasSelector:(SEL)selector {
    Class cls = object_getClass(self);
    unsigned int count = 0;
    Method * methods = class_copyMethodList(cls, &count);
    for (int i = 0; i < count; i++) {
        SEL currentSelector = method_getName(methods[i]);
        if (currentSelector == selector) {
            free(methods);
            return YES;
        }
    }
    free(methods);
    return NO;
}

@end
