// SambaFixNet.m  (diagnostico de red)
// Registra las URLs que usa el juego (NSURLSession) en:
//   - una capa verde en pantalla (haz captura cuando se quede en negro)
//   - Documents/SambaFix-net.log dentro del contenedor del juego
// No bloquea ni modifica ninguna peticion; solo la anota.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define SF_OVERLAY 0
#define SF_MAX_LINES 14

static NSMutableArray<NSString *> *gLines;
static NSString *gLogPath;
static NSString *gLast;
static UILabel *gLabel;
static UIWindow *gWindow;
static dispatch_queue_t gQ;

static void SFRefreshOverlay(void) {
#if SF_OVERLAY
    NSString *text = [gLines componentsJoinedByString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gLabel) gLabel.text = text;
    });
#endif
}

static void SFNetLog(NSString *line) {
    NSLog(@"[SambaFix-net] %@", line);
    dispatch_async(gQ, ^{
        if ([line isEqualToString:gLast]) return; // evita duplicados seguidos
        gLast = line;

        NSString *short_ = line.length > 110 ? [line substringToIndex:110] : line;
        [gLines addObject:short_];
        while (gLines.count > SF_MAX_LINES) [gLines removeObjectAtIndex:0];

        NSString *full = [NSString stringWithFormat:@"%@  %@\n", [NSDate date], line];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
        if (!fh) {
            [full writeToFile:gLogPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
        } else {
            [fh seekToEndOfFile];
            [fh writeData:[full dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
        SFRefreshOverlay();
    });
}

#pragma mark - Protocolo que solo anota

@interface SFLogProtocol : NSURLProtocol
@end

@implementation SFLogProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (request.URL) {
        SFNetLog([NSString stringWithFormat:@"%@ %@",
                  request.HTTPMethod ?: @"GET", request.URL.absoluteString]);
    }
    return NO; // no lo manejamos nosotros, sigue su camino normal
}
@end

#pragma mark - Inserta el protocolo en las sesiones

static NSArray *(*orig_protocolClasses)(id, SEL);

static NSArray *new_protocolClasses(id self, SEL _cmd) {
    NSArray *orig = orig_protocolClasses ? orig_protocolClasses(self, _cmd) : nil;
    NSMutableArray *a = [NSMutableArray arrayWithObject:[SFLogProtocol class]];
    if (orig) [a addObjectsFromArray:orig];
    return a;
}

static void hookConfig(void) {
    NSArray *names = @[@"__NSCFURLSessionConfiguration", @"NSURLSessionConfiguration"];
    for (NSString *n in names) {
        Class c = NSClassFromString(n);
        Method m = c ? class_getInstanceMethod(c, @selector(protocolClasses)) : NULL;
        if (m) {
            orig_protocolClasses = (NSArray *(*)(id, SEL))method_getImplementation(m);
            method_setImplementation(m, (IMP)new_protocolClasses);
            NSLog(@"[SambaFix-net] hook protocolClasses en %@", n);
            return;
        }
    }
    NSLog(@"[SambaFix-net] no se pudo enganchar protocolClasses");
}

#pragma mark - Capa en pantalla

static void SFShowOverlay(void) {
#if SF_OVERLAY
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gWindow) return;
        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
        }
        if (!scene) return;

        gWindow = [[UIWindow alloc] initWithWindowScene:scene];
        gWindow.windowLevel = UIWindowLevelAlert + 100;
        gWindow.userInteractionEnabled = NO;
        gWindow.backgroundColor = [UIColor clearColor];
        UIViewController *vc = [UIViewController new];
        vc.view.userInteractionEnabled = NO;
        vc.view.backgroundColor = [UIColor clearColor];
        gWindow.rootViewController = vc;

        CGFloat w = scene.coordinateSpace.bounds.size.width;
        gLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 50, w - 16, 260)];
        gLabel.numberOfLines = 0;
        gLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
        gLabel.textColor = [UIColor greenColor];
        gLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        gLabel.text = @"[SambaFix-net] esperando peticiones...";
        [vc.view addSubview:gLabel];
        gWindow.hidden = NO;
        SFRefreshOverlay();
    });
#endif
}

__attribute__((constructor))
static void SambaFixNet_init(void) {
    gLines = [NSMutableArray array];
    gQ = dispatch_queue_create("sambafix.net", DISPATCH_QUEUE_SERIAL);
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    gLogPath = [docs stringByAppendingPathComponent:@"SambaFix-net.log"];
    [[NSFileManager defaultManager] removeItemAtPath:gLogPath error:nil];

    hookConfig();
    [NSURLProtocol registerClass:[SFLogProtocol class]];

    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil queue:nil
                usingBlock:^(NSNotification *n) { SFShowOverlay(); }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{ SFShowOverlay(); });

    NSLog(@"[SambaFix-net] cargado, log en %@", gLogPath);
}
