import AppKit

@MainActor final class ChromeFade: NSAnimation {
    private let update: (CGFloat) -> Void
    private let start: CGFloat
    private let end: CGFloat

    init(from start: CGFloat, to end: CGFloat, seconds: TimeInterval, update: @escaping (CGFloat) -> Void) {
        self.start = start
        self.end = end
        self.update = update
        super.init(duration: seconds, animationCurve: .easeOut)
        animationBlockingMode = .nonblocking
        frameRate = 60
    }

    required init?(coder: NSCoder) { fatalError() }
    override var currentProgress: NSAnimation.Progress {
        didSet { update(start + (end - start) * CGFloat(currentValue)) }
    }
}

enum ChromeSymbol: Sendable { case back, forward, reload, plus, close, placement, shield, more, page }

@MainActor func chromeImage(_ symbol: ChromeSymbol) -> NSImage {
    let image = NSImage(size:NSSize(width:18,height:18),flipped:true) { rect in
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let transform=NSAffineTransform();transform.scale(by:0.75);transform.concat()
        NSColor.black.setStroke();NSColor.black.setFill()
        let path=NSBezierPath();path.lineWidth=1.6;path.lineCapStyle = .round;path.lineJoinStyle = .round
        func line(_ points:[NSPoint]) { guard let first=points.first else{return};path.move(to:first);for point in points.dropFirst(){path.line(to:point)} }
        switch symbol {
        case .back:line([.init(x:14,y:5),.init(x:7,y:12),.init(x:14,y:19)]);line([.init(x:7,y:12),.init(x:21,y:12)])
        case .forward:line([.init(x:10,y:5),.init(x:17,y:12),.init(x:10,y:19)]);line([.init(x:3,y:12),.init(x:17,y:12)])
        case .reload:path.appendArc(withCenter:.init(x:12,y:12),radius:8,startAngle:35,endAngle:320,clockwise:false);line([.init(x:19,y:3),.init(x:19,y:9),.init(x:13,y:9)])
        case .plus:line([.init(x:12,y:4),.init(x:12,y:20)]);line([.init(x:4,y:12),.init(x:20,y:12)])
        case .close:line([.init(x:6,y:6),.init(x:18,y:18)]);line([.init(x:18,y:6),.init(x:6,y:18)])
        case .placement:path.appendRect(NSRect(x:3,y:4,width:18,height:16));line([.init(x:9,y:4),.init(x:9,y:20)])
        case .shield:line([.init(x:12,y:3),.init(x:20,y:6),.init(x:19,y:13),.init(x:16,y:18),.init(x:12,y:21),.init(x:8,y:18),.init(x:5,y:13),.init(x:4,y:6),.init(x:12,y:3)]);line([.init(x:8,y:11),.init(x:11,y:14),.init(x:16,y:9)])
        case .more:for x in [5,12,19]{NSBezierPath(ovalIn:NSRect(x:Double(x)-1,y:11,width:2,height:2)).fill()}
        case .page:line([.init(x:6,y:3),.init(x:14,y:3),.init(x:19,y:8),.init(x:19,y:21),.init(x:6,y:21),.init(x:6,y:3)]);line([.init(x:14,y:3),.init(x:14,y:8),.init(x:19,y:8)])
        }
        path.stroke();return true
    }
    image.isTemplate=true;return image
}

@MainActor final class ChromeButton: NSButton {
    var selectedStyle=false { didSet{if oldValue != selectedStyle{updateInk();needsDisplay=true}} }
    var outlined=false
    var hoverEnabled=true
    var onMiddleClick:(()->Void)?
    private var hoverAmount: CGFloat = 0
    private var hoverFade: ChromeFade?
    private var tracking:NSTrackingArea?
    override var title:String { didSet{if oldValue != title{updateInk()}} }
    init(title:String="",symbol:ChromeSymbol?=nil,target:AnyObject,action:Selector){
        super.init(frame:.zero)
        self.title=title;self.target=target;self.action=action
        isBordered=false;bezelStyle = .inline;focusRingType = .none
        font=NSFont(name:"Arial",size:14)
        if let symbol{image=chromeImage(symbol);imagePosition=title.isEmpty ? .imageOnly:.imageLeading;imageScaling = .scaleNone}
        setAccessibilityLabel(title)
        updateInk()
    }
    required init?(coder:NSCoder){fatalError()}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool{true}
    override func updateTrackingAreas(){super.updateTrackingAreas();if let tracking{removeTrackingArea(tracking)};tracking=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil);addTrackingArea(tracking!)}
    override func mouseEntered(with event: NSEvent) { if hoverEnabled { setHoverAmount(1) } }
    override func mouseExited(with event: NSEvent) { if hoverEnabled { setHoverAmount(0) } }
    override func viewDidHide() {
        super.viewDidHide()
        hoverFade?.stop()
        hoverAmount = 0
        needsDisplay = true
    }
    private func setHoverAmount(_ amount: CGFloat) {
        hoverFade?.stop()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            hoverAmount = amount
            needsDisplay = true
            return
        }
        let fade = ChromeFade(from: hoverAmount, to: amount, seconds: 0.12) { [weak self] value in
            self?.hoverAmount = value
            self?.needsDisplay = true
        }
        hoverFade = fade
        fade.start()
    }
    override func viewDidChangeEffectiveAppearance(){super.viewDidChangeEffectiveAppearance();updateInk()}
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();updateInk()}
    private func updateInk(){
        let ink=selectedStyle ? Palette.background(self):Palette.text(self)
        contentTintColor=ink
        if !title.isEmpty{attributedTitle=NSAttributedString(string:title,attributes:[.font:font ?? NSFont.systemFont(ofSize:14),.foregroundColor:ink])}
    }
    override func otherMouseDown(with event:NSEvent){if event.buttonNumber == 2{onMiddleClick?()}else{super.otherMouseDown(with:event)}}
    override func draw(_ dirtyRect:NSRect){
        let rect=bounds.insetBy(dx:0.5,dy:0.5),shape=NSBezierPath(roundedRect:rect,xRadius:5,yRadius:5)
        if selectedStyle{Palette.text(self).setFill();shape.fill()}
        else {
            if outlined { Palette.address(self).setFill(); shape.fill() }
            if isHighlighted || hoverAmount > 0 {
                Palette.hover(self).withAlphaComponent(isHighlighted ? 1 : hoverAmount).setFill()
                shape.fill()
            }
        }
        if outlined{Palette.line(self).setStroke();shape.lineWidth=1;shape.stroke()}
        super.draw(dirtyRect)
    }
}

@MainActor final class NewTabView: Surface {
    weak var controller:BrowserWindow?
    private let wallpaper = NewTabWallpaperView()
    private let wordmark=NSTextField(labelWithString:"sisu")
    private let field=RoundedField()
    private var searchButton:ChromeButton!
    init(controller:BrowserWindow){
        self.controller=controller;super.init(frame:.zero)
        searchButton=ChromeButton(title:"Search",target:self,action:#selector(search))
        searchButton.selectedStyle=true;searchButton.setAccessibilityLabel("Search")
        field.isSearchField=true;field.rightPadding=108;field.font=NSFont(name:"Arial",size:15)
        field.target=self;field.action = #selector(search);field.setAccessibilityLabel("New tab search")
        addSubview(wallpaper);addSubview(wordmark);addSubview(field);addSubview(searchButton);updateProvider()
    }
    required init?(coder:NSCoder){fatalError()}
    func updateProvider(){field.placeholderString="Search with " + (controller?.profile.preferences.google == true ? "Google":"DuckDuckGo")}
    override func layout(){
        super.layout()
        wallpaper.frame = bounds
        let width=min(584,bounds.width*0.84),size=min(88,max(62,bounds.width*0.09))
        let top=max(24,(bounds.height-(size+38+58))/2-bounds.height*0.04)
        wordmark.frame=NSRect(x:0,y:top,width:bounds.width,height:size+8)
        field.frame=NSRect(x:(bounds.width-width)/2,y:top+size+38,width:width,height:58)
        searchButton.frame=NSRect(x:field.frame.maxX-89,y:field.frame.minY+6,width:83,height:46)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        wordmark.attributedStringValue = NSAttributedString(string: "sisu", attributes: [
            .font: NSFont(name: "Arial", size: size) ?? .systemFont(ofSize: size),
            .kern: -size * 0.065,
            .foregroundColor: Palette.text(self),
            .paragraphStyle: paragraph
        ])
    }
    override func viewDidChangeEffectiveAppearance(){super.viewDidChangeEffectiveAppearance();needsLayout=true}
    @objc private func search(){controller?.navigate(field.stringValue)}
}

@MainActor final class SettingsView: Surface {
    weak var controller:BrowserWindow?
    private let scroll=NSScrollView()
    private let content=Surface()
    private var elements:[String:NSView]=[:]
    private var choices:[Int:ChromeButton]=[:]
    private let widthField=RoundedField()
    init(controller:BrowserWindow){
        self.controller=controller;super.init(frame:.zero)
        scroll.documentView=content;scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;addSubview(scroll)
        func label(_ key:String,_ text:String,_ size:CGFloat=14,_ muted:Bool=false){let field=NSTextField(labelWithString:text);field.font=NSFont(name:"Arial",size:size);field.textColor=muted ? .secondaryLabelColor:.labelColor;content.addSubview(field);elements[key]=field}
        label("title","Settings",37)
        label("profile",controller.profile.isPrivate ? "Changes last for this private window.":"Preferences for this profile",14,true)
        for (key,text) in [("appearance","Appearance"),("browsing","Browsing"),("privacy","Privacy and data")]{label(key,text,14,true)}
        for (key,text) in [("theme","Color mode"),("tabs","Tab placement"),("width","Sidebar width (92–350 px)"),("provider","Search engine"),("blocking","Native blocking"),("tools","Browser tools")]{label(key,text)}
        for (tag,title) in [(0,"Dark"),(1,"Light"),(2,"Top"),(3,"Left"),(4,"DuckDuckGo"),(5,"Google"),(6,"On"),(7,"Off"),(8,"Apply"),(9,"New private window"),(10,"About Sisu")]{
            let button=ChromeButton(title:title,target:self,action:#selector(change(_:)));button.tag=tag;button.outlined=true;choices[tag]=button;content.addSubview(button)
        }
        widthField.font=NSFont(name:"Arial",size:14);widthField.alignment = .center;widthField.stringValue=String(controller.profile.preferences.sidebarWidth);widthField.target=self;widthField.action = #selector(applyWidth);widthField.setAccessibilityLabel("Sidebar width in pixels");content.addSubview(widthField)
        label("note","Reload open pages after changing blocking.",14)
        label("version","Sisu \(Bundle.main.object(forInfoDictionaryKey:"SisuVersion") as? String ?? "alpha") · Apache 2.0",13,true)
        refreshChoices()
    }
    required init?(coder:NSCoder){fatalError()}
    private func refreshChoices(){guard let p=controller?.profile.preferences else{return};for (tag,button) in choices{button.selectedStyle = (tag==0 && p.theme=="dark") || (tag==1 && p.theme=="light") || (tag==2 && p.placement=="top") || (tag==3 && p.placement=="left") || (tag==4 && !p.google) || (tag==5 && p.google) || (tag==6 && p.blocking) || (tag==7 && !p.blocking)}}
    override func layout(){
        super.layout();scroll.frame=bounds
        let width=min(720,max(180,bounds.width-48)),x=(bounds.width-width)/2,stacked=width<520
        var y:CGFloat=28
        func place(_ key:String,_ h:CGFloat){elements[key]?.frame=NSRect(x:x,y:y,width:width,height:h);y += h}
        func group(_ key:String){place(key,24);y += 8}
        func row(_ label:String,_ a:Int,_ b:Int){let right=stacked ? x:x+width/2,rw=stacked ? width:width/2;elements[label]?.frame=NSRect(x:x,y:y+7,width:stacked ? width:width/2-8,height:24);if stacked{y += 25};choices[a]?.frame=NSRect(x:right,y:y,width:(rw-8)/2,height:33);choices[b]?.frame=NSRect(x:right+(rw+8)/2,y:y,width:(rw-8)/2,height:33);y += 41}
        place("title",48);y += 3;place("profile",25);y += 22
        group("appearance");row("theme",0,1);row("tabs",2,3)
        elements["width"]?.frame=NSRect(x:x,y:y+7,width:stacked ? width:width/2-8,height:24);if stacked{y += 25};let right=stacked ? x:x+width/2;widthField.frame=NSRect(x:right,y:y,width:100,height:33);choices[8]?.frame=NSRect(x:right+108,y:y,width:86,height:33);y += 55
        group("browsing");row("provider",4,5);y += 14
        group("privacy");row("blocking",6,7);place("note",24);y += 16;row("tools",9,10);y += 20;place("version",24)
        content.frame=NSRect(x:0,y:0,width:bounds.width,height:max(bounds.height,y+28))
    }
    @objc private func applyWidth(){guard let controller else{return};guard let width=Int(widthField.stringValue),(92...350).contains(width) else{NSSound.beep();widthField.stringValue=String(controller.profile.preferences.sidebarWidth);return};controller.setSidebarWidth(width)}
    @objc private func change(_ sender:NSButton){guard let controller else{return};switch sender.tag {
        case 0:controller.setTheme("dark")
        case 1:controller.setTheme("light")
        case 2:controller.setPlacement("top")
        case 3:controller.setPlacement("left")
        case 4:controller.setProvider(false)
        case 5:controller.setProvider(true)
        case 6:controller.setBlocking(true)
        case 7:controller.setBlocking(false)
        case 8:applyWidth()
        case 9:(NSApp.delegate as? AppDelegate)?.newPrivateWindow()
        default:(NSApp.delegate as? AppDelegate)?.about()
        };refreshChoices()
    }
}
