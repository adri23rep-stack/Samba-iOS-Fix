// SambaFix.m  (v3)
// Samba de Amigo + LiveContainer: CloudKit falso que "funciona" pero sin datos.
//
// v1: devolvia nil            -> el juego se quedaba esperando (pantalla negra).
// v2: iCloud falso con error  -> el juego arrancaba pero mostraba el aviso
//                                "No se ha podido obtener datos de la nube".
// v3: iCloud falso "disponible": la cuenta existe y toda operacion termina bien,
//                                con resultados vacios. Sin errores = sin aviso.

#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// Si el juego se comporta raro, prueba CKAccountStatusNoAccount (como la v2)
#define SF_ACCOUNT_STATUS CKAccountStatusAvailable

static void SFMain(dispatch_block_t b) { dispatch_async(dispatch_get_main_queue(), b); }

#pragma mark - Completa cualquier operacion de base de datos "con exito" y sin datos

static void SFComplete(CKDatabaseOperation *op) {
    NSLog(@"[SambaFix] operacion %@ -> exito vacio", NSStringFromClass([op class]));

    if ([op isKindOfClass:[CKModifyRecordsOperation class]]) {
        CKModifyRecordsOperation *o = (CKModifyRecordsOperation *)op;
        SFMain(^{
            for (CKRecord *r in o.recordsToSave ?: @[])
                if (o.perRecordSaveBlock) o.perRecordSaveBlock(r.recordID, r, nil);
            for (CKRecordID *i in o.recordIDsToDelete ?: @[])
                if (o.perRecordDeleteBlock) o.perRecordDeleteBlock(i, nil);
            if (o.modifyRecordsCompletionBlock)
                o.modifyRecordsCompletionBlock(o.recordsToSave, o.recordIDsToDelete, nil);
            if (o.modifyRecordsResultBlock) o.modifyRecordsResultBlock(nil);
        });
    } else if ([op isKindOfClass:[CKFetchRecordsOperation class]]) {
        CKFetchRecordsOperation *o = (CKFetchRecordsOperation *)op;
        SFMain(^{
            if (o.fetchRecordsCompletionBlock) o.fetchRecordsCompletionBlock(@{}, nil);
            if (o.fetchRecordsResultBlock) o.fetchRecordsResultBlock(nil);
        });
    } else if ([op isKindOfClass:[CKQueryOperation class]]) {
        CKQueryOperation *o = (CKQueryOperation *)op;
        SFMain(^{
            if (o.queryCompletionBlock) o.queryCompletionBlock(nil, nil);
            if (o.queryResultBlock) o.queryResultBlock(nil, nil);
        });
    } else if ([op isKindOfClass:[CKFetchRecordZonesOperation class]]) {
        CKFetchRecordZonesOperation *o = (CKFetchRecordZonesOperation *)op;
        SFMain(^{
            if (o.fetchRecordZonesCompletionBlock) o.fetchRecordZonesCompletionBlock(@{}, nil);
            if (o.fetchRecordZonesResultBlock) o.fetchRecordZonesResultBlock(nil);
        });
    } else if ([op isKindOfClass:[CKModifyRecordZonesOperation class]]) {
        CKModifyRecordZonesOperation *o = (CKModifyRecordZonesOperation *)op;
        SFMain(^{
            if (o.modifyRecordZonesCompletionBlock)
                o.modifyRecordZonesCompletionBlock(o.recordZonesToSave, o.recordZoneIDsToDelete, nil);
            if (o.modifyRecordZonesResultBlock) o.modifyRecordZonesResultBlock(nil);
        });
    } else if ([op isKindOfClass:[CKModifySubscriptionsOperation class]]) {
        CKModifySubscriptionsOperation *o = (CKModifySubscriptionsOperation *)op;
        SFMain(^{
            if (o.modifySubscriptionsCompletionBlock)
                o.modifySubscriptionsCompletionBlock(o.subscriptionsToSave, o.subscriptionIDsToDelete, nil);
            if (o.modifySubscriptionsResultBlock) o.modifySubscriptionsResultBlock(nil);
        });
    } else {
        NSLog(@"[SambaFix] tipo de operacion sin manejar: %@", NSStringFromClass([op class]));
    }
}

#pragma mark - Base de datos falsa

@interface SFDatabase : CKDatabase
@end

@implementation SFDatabase

- (void)addOperation:(CKDatabaseOperation *)operation {
    SFComplete(operation);
}

- (void)fetchRecordWithID:(CKRecordID *)recordID
        completionHandler:(void (^)(CKRecord *, NSError *))handler {
    NSLog(@"[SambaFix] fetchRecordWithID -> no existe");
    NSError *e = [NSError errorWithDomain:CKErrorDomain code:CKErrorUnknownItem userInfo:nil];
    if (handler) SFMain(^{ handler(nil, e); });
}

- (void)saveRecord:(CKRecord *)record
 completionHandler:(void (^)(CKRecord *, NSError *))handler {
    NSLog(@"[SambaFix] saveRecord -> exito");
    if (handler) SFMain(^{ handler(record, nil); });
}

- (void)deleteRecordWithID:(CKRecordID *)recordID
         completionHandler:(void (^)(CKRecordID *, NSError *))handler {
    NSLog(@"[SambaFix] deleteRecordWithID -> exito");
    if (handler) SFMain(^{ handler(recordID, nil); });
}

@end

#pragma mark - Contenedor falso

static CKDatabase *gDB = nil;
static CKContainer *gContainer = nil;

@interface SFContainer : CKContainer
@end

@implementation SFContainer

- (void)accountStatusWithCompletionHandler:(void (^)(CKAccountStatus, NSError *))handler {
    NSLog(@"[SambaFix] accountStatus -> %ld", (long)SF_ACCOUNT_STATUS);
    if (handler) SFMain(^{ handler(SF_ACCOUNT_STATUS, nil); });
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

    gDB = class_createInstance([SFDatabase class], 0);
    gContainer = class_createInstance([SFContainer class], 0);

    hookClassMethod(cls, @selector(defaultContainer), (IMP)fix_defaultContainer);
    hookClassMethod(cls, @selector(containerWithIdentifier:), (IMP)fix_containerWithIdentifier);

    NSLog(@"[SambaFix] v3 cargado");
}
