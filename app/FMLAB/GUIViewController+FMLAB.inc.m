// FMLAB Linux: aggiunte FMLAB al visore del desktop di LinuxRunner (LRGUIViewController), tenute fuori dal file
// originale. Si include dentro @implementation LRGUIViewController (GUIViewController.m): vede le stesse variabili.
//   - misura "Telefono" nitida (pixel interi) anche in verticale, banda della fotocamera esclusa
//   - lato della Dynamic Island in orizzontale (banda nera solo da quella parte)
//   - rotazione del desktop insieme al telefono (fmlab-ruota.sh, senza riavviare)
//   - margini scritti per RunnerKit/TouchPad (parte coperta da isola, angoli, indicatore Home)

// FMLAB 0.7.0: "Phone" reads the screen and picks the sharpest size by itself.
// It divides the screen's real pixels by a whole number (2, 3…) so that every Linux pixel becomes an exact
// square of iPhone pixels (sharp, no uneven rows), choosing the division that gives 540–720 rows.
// iPhone 15 Pro Max: (2796 − 177 della fotocamera)×1290 pixels ÷ 2 = 1308×644 (0.8.5; prima 1398×644) (before: 1168×540 stretched 2.39×, slightly blocky).
// If the phone is hot (thermal state Serious/Critical) or in Low Power Mode it uses the lighter 540-row size,
// so the desktop never pushes a hot phone harder. An external monitor keeps the previous rule.
- (NSString *)fmlabPhoneGeometry{
    // In verticale (telefono dritto) la stessa misura girata: 644×1398 invece di 1398×644.
    NSString *g=[self fmlabPhoneGeometryOrizzontale];unsigned w=0,h=0;CGSize v=self.view.bounds.size;
    if(![self externalOutputActive]&&v.height>v.width&&sscanf(g.UTF8String,"%ux%u",&w,&h)==2)return [NSString stringWithFormat:@"%ux%u",h,w];
    return g;
}

- (NSString *)fmlabPhoneGeometryOrizzontale{
    UIWindow *target=([self externalOutputActive]?LRCurrentExternalDisplay.view.window:nil)?:self.view.window;
    CGSize s=target?target.bounds.size:UIScreen.mainScreen.bounds.size;
    CGFloat lungo=MAX(s.width,s.height),corto=MAX(1,MIN(s.width,s.height));
    unsigned W540=(unsigned)(540.0*lungo/corto);W540=MIN(1600u,MAX(960u,W540/8*8));
    NSString *leggera=[NSString stringWithFormat:@"%ux540",W540];
    if([self externalOutputActive])return leggera;
    NSProcessInfoThermalState caldo=NSProcessInfo.processInfo.thermalState;
    if(caldo>=NSProcessInfoThermalStateSerious||NSProcessInfo.processInfo.lowPowerModeEnabled){
        [LRRuntimeBridge logCategory:@"FMLAB_DISPLAY" event:[NSString stringWithFormat:@"phone geometry=%@ reason=%@",leggera,caldo>=NSProcessInfoThermalStateSerious?@"thermal":@"low-power"]];
        return leggera;
    }
    CGSize nativo=UIScreen.mainScreen.nativeBounds.size;   // real pixels, portrait (15 Pro Max: 1290×2796)
    unsigned pl=(unsigned)MAX(nativo.width,nativo.height),pc=(unsigned)MIN(nativo.width,nativo.height);
    // FMLAB 0.8.5: la banda della fotocamera non è desktop: lato lungo meno la zona sicura (15 Pro Max: 59 pt × 3)
    if(UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPhone){UIEdgeInsets si=self.view.window.safeAreaInsets;
        CGFloat isola=MAX(MAX(si.left,si.right),si.top)*UIScreen.mainScreen.nativeScale;if(isola>0&&isola<pl/4)pl-=(unsigned)isola;}
    for(unsigned k=2;k<=4&&pc>0;k++){
        unsigned H=pc/k/2*2,W=pl/k/2*2;   // session.sh wants even sizes up to 2560×1600
        if(H>=540&&H<=720&&W<=2560){
            NSString *g=[NSString stringWithFormat:@"%ux%u",W,H];
            [LRRuntimeBridge logCategory:@"FMLAB_DISPLAY" event:[NSString stringWithFormat:@"phone geometry=%@ native=%ux%u divisor=%u",g,pl,pc,k]];
            return g;
        }
    }
    return leggera;
}

- (void)fmlabLatoFotocamera{
    if(!_fmlabSinistra)return;
    CGFloat l=0,r=0;UIEdgeInsets ins=self.view.window.safeAreaInsets;
    if(_desktopMode&&_inputToolbar.hidden&&UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPhone&&MAX(ins.left,ins.right)>0){
        UIInterfaceOrientation o=self.view.window.windowScene.interfaceOrientation;
        if(o==UIInterfaceOrientationLandscapeRight)l=ins.left;else if(o==UIInterfaceOrientationLandscapeLeft)r=ins.right;
    }
    if(_fmlabSinistra.constant!=l)_fmlabSinistra.constant=l;
    if(_fmlabDestra.constant!=r)_fmlabDestra.constant=r;
}

// FMLAB 0.8: giri il telefono -> lo schermo di Linux si gira (orizzontale 1398×644 <-> verticale 644×1398) senza
// riavviare il desktop: la sessione lancia fmlab-ruota.sh (xrandr) e x11vnc manda al visore la misura nuova.
- (void)fmlabRuotaVerso:(CGSize)size{
    if(!_desktopMode||!_sessionURL||_sessionTerminal.sessionPid<=0||_resolution.selectedSegmentIndex!=5||[self externalOutputActive])return;
    if(![NSFileManager.defaultManager fileExistsAtPath:[_sessionURL URLByAppendingPathComponent:@"fmlab-rotazione"].path])return;
    NSString *g=[NSString stringWithContentsOfURL:[_sessionURL URLByAppendingPathComponent:@"geometry"] encoding:NSUTF8StringEncoding error:nil];
    unsigned a=0,b=0;if(!g||sscanf(g.UTF8String,"%ux%u",&a,&b)!=2)return;
    unsigned L=MAX(a,b),S=MIN(a,b);BOOL verticale=size.height>size.width;unsigned W=verticale?S:L,H=verticale?L:S;
    if(_surface.pixelWidth==W&&_surface.pixelHeight==H)return;
    [LRRuntimeBridge logCategory:@"FMLAB_DISPLAY" event:[NSString stringWithFormat:@"rotate to %ux%u",W,H]];
    NSString *script=[NSString stringWithFormat:@"/home/mobile/Downloads/%@/fmlab-ruota.sh",LRGUIFolder];
    [self launchDesktopApplication:@{@"executable":@"/bin/sh",@"directory":@"/",@"arguments":@[script,[NSString stringWithFormat:@"%u",W],[NSString stringWithFormat:@"%u",H]],
                                     @"environment":@{},@"requestID":NSUUID.UUID.UUIDString}];
}

// FMLAB 0.7.2: a schermo intero il desktop va sotto la Dynamic Island, gli angoli arrotondati e l'indicatore
// Home. Si scrive nella cartella della sessione quanta parte del desktop (in pixel di Linux) cade lì, così
// RunnerKit/TouchPad tiene i suoi pallini e finestre nella parte visibile. Si scrive solo se cambia.
- (void)fmlabScriviMargini{
    if(!_desktopMode||!_sessionURL||!_surface.pixelWidth||!_surface.pixelHeight)return;
    // Il lato della fotocamera non fa parte del desktop (banda nera): resta coperta solo la riga dell'indicatore Home.
    BOOL pieno=_inputToolbar.hidden;CGSize v=_surface.bounds.size;UIEdgeInsets m=pieno?UIEdgeInsetsMake(0,0,self.view.safeAreaInsets.bottom,0):UIEdgeInsetsZero;
    if(v.width<1||v.height<1)return;
    CGFloat sx=_surface.pixelWidth/v.width,sy=_surface.pixelHeight/v.height;
    NSString *testo=[NSString stringWithFormat:@"# FMLAB Linux: parte del desktop coperta da Dynamic Island, angoli e indicatore Home (pixel di Linux)\nmargini=%d %d %d %d\nschermo_intero=%d\nlarghezza=%u\naltezza=%u\n",
        (int)ceil(m.left*sx),(int)ceil(m.top*sy),(int)ceil(m.right*sx),(int)ceil(m.bottom*sy),pieno?1:0,_surface.pixelWidth,_surface.pixelHeight];
    if([testo isEqualToString:_fmlabUltimiMargini])return;
    NSURL *url=[_sessionURL URLByAppendingPathComponent:@"fmlab-schermo"];
    if([testo writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil]){
        [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:url.path error:nil];_fmlabUltimiMargini=testo;}
}
