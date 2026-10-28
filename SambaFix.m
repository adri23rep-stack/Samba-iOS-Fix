// SambaFix.m
// Evita el crasheo de Samba de Amigo en LiveContainer causado por CloudKit.
//
// Causa: CloudKitWrapper llama a +[CKContainer defaultContainer] al iniciar,
// y sin el entitlement de iCloud (se pierde al re-firmar) CloudKit aborta el proceso.
// Solución: interceptar esos métodos y devolver nil en vez de dejar que CloudKit aborte.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// +[CKContainer defaultContainer]
static id fix_defaultContainer(id self, SEL _cmd) {
    NSLog(@"[SambaFix] +[CKContainer defaultContainer] interceptado -> nil");
    return nil;
}

// +[CKContainer containerWithIdentifier:]
static id fix_containerWithIdentifier(id self, SEL _cmd, NSString *identifier) {
    NSLog(@"[SambaFix] +[CKContainer containerWithIdentifier:%@] interceptado -> nil", identifier);
    return nil;
}

static void hookClassMethod(Class cls, SEL sel, IMP newImp) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) {
        NSLog(@"[SambaFix] no se encontro el metodo %@", NSStringFromSelector(sel));
        return;
    }
    method_setImplementation(m, newImp);
    NSLog(@"[SambaFix] hook aplicado a %@", NSStringFromSelector(sel));
}

__attribute__((constructor))
static void SambaFix_init(void) {
    // Asegura que CloudKit este cargado antes de buscar la clase
    dlopen("/System/Library/Frameworks/CloudKit.framework/CloudKit", RTLD_NOW);

    Class cls = objc_getClass("CKContainer");
    if (!cls) {
        NSLog(@"[SambaFix] CKContainer no existe, no se aplica nada");
        return;
    }

    hookClassMethod(cls, @selector(defaultContainer), (IMP)fix_defaultContainer);
    hookClassMethod(cls, @selector(containerWithIdentifier:), (IMP)fix_containerWithIdentifier);

    NSLog(@"[SambaFix] cargado");
}
