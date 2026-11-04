// FMLAB Linux: traduzione della parte Objective-C (schermo del desktop, menu, avvisi, barre).
// Incluso solo da app/main.m. I testi italiani sono in it.lproj/Localizable.strings, generato da
// strumenti/genera_lingue.py (che ferma la compilazione se un testo a schermo non ha la traduzione).
//
// Perché così: i file di LinuxRunner originale restano quasi uguali (gli aggiornamenti dell'originale si portano
// dentro senza conflitti). Invece di cambiare centinaia di righe, i testi vengono tradotti nel momento in cui
// finiscono a schermo (etichette, pulsanti, menu, avvisi, titoli, segmenti, scorciatoie da tastiera).
// I testi con valori dentro (es. "Desktop pronto · 45 s") passano da FMLABTr() nel punto in cui si compongono.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL FMLABItaliano = NO;
static NSString *const FMLABAssente = @"⁣FMLAB?";

NSString *FMLABTr(NSString *s) {
    if (!FMLABItaliano || ![s isKindOfClass:NSString.class] || s.length == 0 || s.length > 2000) return s;
    NSString *t = [NSBundle.mainBundle localizedStringForKey:s value:FMLABAssente table:nil];
    if (t != nil && ![t isEqualToString:FMLABAssente]) return t;
    // Testi composti da più paragrafi già tradotti uno per uno ("Titolo\n\nSpiegazione").
    if ([s containsString:@"\n"]) {
        NSArray<NSString *> *parti = [s componentsSeparatedByString:@"\n"];
        NSMutableArray<NSString *> *tradotte = [NSMutableArray arrayWithCapacity:parti.count];
        BOOL cambiato = NO;
        for (NSString *p in parti) {
            NSString *q = p.length ? [NSBundle.mainBundle localizedStringForKey:p value:FMLABAssente table:nil] : p;
            if (q.length && ![q isEqualToString:FMLABAssente]) { [tradotte addObject:q]; cambiato = YES; }
            else [tradotte addObject:p];
        }
        if (cambiato) return [tradotte componentsJoinedByString:@"\n"];
    }
    return s;
}

// Ogni classe ha il suo nome di metodo (fmlab_vc_, fmlab_nav_, fmlab_bar_…): con lo stesso nome in una classe
// madre e in una figlia (UIViewController e UIAlertController) il metodo richiamava sé stesso all'infinito
// e l'app si chiudeva aprendo il menu Desktop (0.7.0). Il titolo degli avvisi passa già da UIViewController.
// Scambio sicuro: se la classe eredita il metodo, prima lo aggiunge a sé stessa (così non tocca la classe madre).
static void FMLABScambia(Class c, SEL originale, SEL nuovo) {
    Method a = class_getInstanceMethod(c, originale), b = class_getInstanceMethod(c, nuovo);
    if (!a || !b) return;
    if (class_addMethod(c, originale, method_getImplementation(b), method_getTypeEncoding(b)))
        class_replaceMethod(c, nuovo, method_getImplementation(a), method_getTypeEncoding(a));
    else
        method_exchangeImplementations(a, b);
}

@implementation UILabel (FMLABLingua)
- (void)fmlab_setText:(NSString *)text { [self fmlab_setText:FMLABTr(text)]; }
@end
@implementation UIButton (FMLABLingua)
- (void)fmlab_setTitle:(NSString *)title forState:(UIControlState)state { [self fmlab_setTitle:FMLABTr(title) forState:state]; }
@end
@implementation UIViewController (FMLABLingua)
- (void)fmlab_vc_setTitle:(NSString *)title { [self fmlab_vc_setTitle:FMLABTr(title)]; }
@end
@implementation UINavigationItem (FMLABLingua)
- (void)fmlab_nav_setTitle:(NSString *)title { [self fmlab_nav_setTitle:FMLABTr(title)]; }
@end
@implementation UIBarButtonItem (FMLABLingua)
- (void)fmlab_bar_setTitle:(NSString *)title { [self fmlab_bar_setTitle:FMLABTr(title)]; }
- (instancetype)fmlab_initWithTitle:(NSString *)title style:(UIBarButtonItemStyle)style target:(id)target action:(SEL)action {
    return [self fmlab_initWithTitle:FMLABTr(title) style:style target:target action:action];
}
@end
@implementation UISegmentedControl (FMLABLingua)
- (instancetype)fmlab_initWithItems:(NSArray *)items {
    NSMutableArray *tradotti = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) [tradotti addObject:[item isKindOfClass:NSString.class] ? FMLABTr(item) : item];
    return [self fmlab_initWithItems:tradotti];
}
- (void)fmlab_seg_setTitle:(NSString *)title forSegmentAtIndex:(NSUInteger)segment { [self fmlab_seg_setTitle:FMLABTr(title) forSegmentAtIndex:segment]; }
@end
@implementation UITextField (FMLABLingua)
- (void)fmlab_setPlaceholder:(NSString *)placeholder { [self fmlab_setPlaceholder:FMLABTr(placeholder)]; }
@end
@implementation UIAlertController (FMLABLingua)
- (void)fmlab_setMessage:(NSString *)message { [self fmlab_setMessage:FMLABTr(message)]; }
+ (instancetype)fmlab_alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style {
    return [self fmlab_alertControllerWithTitle:FMLABTr(title) message:FMLABTr(message) preferredStyle:style];
}
@end
@implementation UIAlertAction (FMLABLingua)
+ (instancetype)fmlab_actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler {
    return [self fmlab_actionWithTitle:FMLABTr(title) style:style handler:handler];
}
@end
@implementation UIAction (FMLABLingua)
+ (instancetype)fmlab_actionWithTitle:(NSString *)title image:(UIImage *)image identifier:(UIActionIdentifier)identifier handler:(UIActionHandler)handler {
    return [self fmlab_actionWithTitle:FMLABTr(title) image:image identifier:identifier handler:handler];
}
@end
@implementation UIKeyCommand (FMLABLingua)
+ (instancetype)fmlab_commandWithTitle:(NSString *)title image:(UIImage *)image action:(SEL)action input:(NSString *)input modifierFlags:(UIKeyModifierFlags)flags propertyList:(id)propertyList {
    return [self fmlab_commandWithTitle:FMLABTr(title) image:image action:action input:input modifierFlags:flags propertyList:propertyList];
}
@end

// Da chiamare in main() dopo aver scelto la lingua. In inglese non cambia niente.
static void FMLABAttivaTraduzione(NSString *lingua) {
    if (![lingua hasPrefix:@"it"]) return;
    FMLABItaliano = YES;
    FMLABScambia(UILabel.class, @selector(setText:), @selector(fmlab_setText:));
    FMLABScambia(UIButton.class, @selector(setTitle:forState:), @selector(fmlab_setTitle:forState:));
    FMLABScambia(UIViewController.class, @selector(setTitle:), @selector(fmlab_vc_setTitle:));
    FMLABScambia(UINavigationItem.class, @selector(setTitle:), @selector(fmlab_nav_setTitle:));
    FMLABScambia(UIBarButtonItem.class, @selector(setTitle:), @selector(fmlab_bar_setTitle:));
    FMLABScambia(UIBarButtonItem.class, @selector(initWithTitle:style:target:action:), @selector(fmlab_initWithTitle:style:target:action:));
    FMLABScambia(UISegmentedControl.class, @selector(initWithItems:), @selector(fmlab_initWithItems:));
    FMLABScambia(UISegmentedControl.class, @selector(setTitle:forSegmentAtIndex:), @selector(fmlab_seg_setTitle:forSegmentAtIndex:));
    FMLABScambia(UITextField.class, @selector(setPlaceholder:), @selector(fmlab_setPlaceholder:));
    FMLABScambia(UIAlertController.class, @selector(setMessage:), @selector(fmlab_setMessage:));
    FMLABScambia(object_getClass(UIAlertController.class), @selector(alertControllerWithTitle:message:preferredStyle:), @selector(fmlab_alertControllerWithTitle:message:preferredStyle:));
    FMLABScambia(object_getClass(UIAlertAction.class), @selector(actionWithTitle:style:handler:), @selector(fmlab_actionWithTitle:style:handler:));
    FMLABScambia(object_getClass(UIAction.class), @selector(actionWithTitle:image:identifier:handler:), @selector(fmlab_actionWithTitle:image:identifier:handler:));
    FMLABScambia(object_getClass(UIKeyCommand.class), @selector(commandWithTitle:image:action:input:modifierFlags:propertyList:), @selector(fmlab_commandWithTitle:image:action:input:modifierFlags:propertyList:));
}
