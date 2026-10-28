// SambaFix.m  (v2)
// Samba de Amigo + LiveContainer: evita el crasheo y la pantalla negra causados por CloudKit.
//
// v1 devolvia nil en +[CKContainer defaultContainer]. El juego pasaba el crash pero se
// quedaba esperando, porque CloudKitWrapper pide el estado de la cuenta de iCloud
// (CKContainer_GetAccountStatus) y con nil nunca llega la respuesta.
//
// v2 devuelve un contenedor FALSO que responde "no hay cuenta de iCloud" de inmediato, y
// una base de datos falsa que responde "no autenticado". Asi el juego sigue sin iCloud.

#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSError *SFError(void) {
    return [NSError errorWithDomain:CKErrorDomain
                               code:CKErrorNotAuthenticated
                           userInfo:@{NSLocalizedDescriptionKey: @"iCloud no disponible (SambaFix)"}];
}

#pragma mark - Base de datos falsa

@interface SFDatabase : CKDatabase
@end

@implementation SFDatabase

- (void)addOperation:(CKDatabaseOperation *)operation {
    NSLog(@"[SambaFix] addOperation ignorada: %@", NSStringFromClass([operation class]));
}

- (void)fetchRecordWithID:(CKRecordID *)recordID
        completionHandler:(void (^)(CKRecord *, NSError *))completionHandler {
    NSLog(@"[SambaFix] fetchRecordWithID -> error");
    if (completionHandler) completionHandler(nil, SFError());
}

- (void)saveRecord:(CKRecord *)record
 completionHandler:(void (^)(CKRecord *, NSError *))completionHandler {
    NSLog(@"[SambaFix] saveRecord -> error");
    if (completionHandler) completionHandler(nil, SFError());
}

- (void)deleteRecordWithID:(CKRecordID *)recordID
         completionHandler:(void (^)(CKRecordID *, NSError *))completionHandler {
    NSLog(@"[SambaFix] deleteRecordWithID -> error");
    if (completionHandler) completionHandler(nil, SFError());
}

@end

#pragma mark - Contenedor falso

static CKDatabase *gDB = nil;
static CKContainer *gContainer = nil;

@interface SFContainer : CKContainer
@end

@implementation SFContainer

- (void)accountStatusWithCompletionHandler:(void (^)(CKAccountStatus, NSError *))handler {
    NSLog(@"[SambaFix] accountStatus -> NoAccount");
    if (!handler) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(CKAccountStatusNoAccount, nil);
    });
}

- (CKDatabase *)privateCloudDatabase { return gDB; }
- (CKDatabase *)publicCloudDatabase  { return gDB; }
- (CKDatabase *)sharedCloudDatabase  { return gDB; }
- (NSString *)containerIdentifier    { return @"iCloud.sambafix.stub"; }

@end

#pragma mark - Hooks

static id fix_defaultContainer(id self, SEL _cmd) {
    NSLog(@"[SambaFix] +[CKContainer defaultContainer] -> contenedor falso");
    return gContainer;
}

static id fix_containerWithIdentifier(id self, SEL _cmd, NSString *identifier) {
    NSLog(@"[SambaFix] +[CKContainer containerWithIdentifier:%@] -> contenedor falso", identifier);
    return gContainer;
}

static void hookClassMethod(Class cls, SEL sel, IMP newImp) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) {
        NSLog(@"[SambaFix] no se encontro %@", NSStringFromSelector(sel));
        return;
    }
    method_setImplementation(m, newImp);
    NSLog(@"[SambaFix] hook aplicado: %@", NSStringFromSelector(sel));
}

__attribute__((constructor))
static void SambaFix_init(void) {
    dlopen("/System/Library/Frameworks/CloudKit.framework/CloudKit", RTLD_NOW);

    Class cls = objc_getClass("CKContainer");
    if (!cls) {
        NSLog(@"[SambaFix] CKContainer no existe, no se aplica nada");
        return;
    }

    // Instancias creadas sin init (el init de CloudKit no esta disponible ni hace falta)
    gDB = class_createInstance([SFDatabase class], 0);
    gContainer = class_createInstance([SFContainer class], 0);

    hookClassMethod(cls, @selector(defaultContainer), (IMP)fix_defaultContainer);
    hookClassMethod(cls, @selector(containerWithIdentifier:), (IMP)fix_containerWithIdentifier);

    NSLog(@"[SambaFix] v2 cargado");
}
