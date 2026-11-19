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

@MainActor class ChromeButton: NSButton {
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
    override func mouseEntered(with event: NSEvent) { if hoverEnabled && isEnabled { setHoverAmount(1) } }
    override func mouseExited(with event: NSEvent) { if hoverEnabled { setHoverAmount(0) } }
    override var isEnabled: Bool {
        didSet { if oldValue != isEnabled { if !isEnabled { hoverFade?.stop(); hoverAmount = 0 }; needsDisplay = true } }
    }
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
            if isEnabled && (isHighlighted || hoverAmount > 0) {
                Palette.hover(self).withAlphaComponent(isHighlighted ? 1 : hoverAmount).setFill()
                shape.fill()
            }
        }
        if outlined{Palette.line(self).setStroke();shape.lineWidth=1;shape.stroke()}
        if let image, !title.isEmpty, imagePosition == .imageLeading { drawCentered(image); return }
        super.draw(dirtyRect)
    }
    /// NSButtonCell pins a leading image to the edge and centres the title in what
    /// is left, so short titles get uneven padding. Centre icon and title as one group.
    private func drawCentered(_ image: NSImage) {
        let ink = (selectedStyle ? Palette.background(self) : Palette.text(self)).withAlphaComponent(isEnabled ? 1 : 0.45)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let label = NSAttributedString(string: title, attributes: [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: ink, .paragraphStyle: paragraph])
        // Centre what is visible: chrome symbols start 2.4 pt into their image, and
        // the title's advance includes trailing side bearing.
        let inset: CGFloat = 2.4, gap: CGFloat = 4, textSize = label.size()
        let textWidth = min(ceil(textSize.width), max(0, bounds.width - 20 - image.size.width - gap))
        let visibleText = min(textWidth, label.boundingRect(with: textSize, options: [.usesLineFragmentOrigin, .usesDeviceMetrics]).maxX)
        var x = (((bounds.width - (image.size.width - inset + gap + visibleText)) / 2 - inset) * 2).rounded() / 2
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect); ink.set(); rect.fill(using: .sourceAtop); return true
        }
        tinted.draw(in: NSRect(x: x, y: ((bounds.height - image.size.height) / 2).rounded(), width: image.size.width, height: image.size.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        x += image.size.width + gap
        label.draw(with: NSRect(x: x, y: ((bounds.height - textSize.height) / 2).rounded(), width: textWidth, height: ceil(textSize.height)),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

@MainActor final class NewTabView: Surface {
    weak var controller:BrowserWindow?
    private let wallpaper = NewTabWallpaperView()
    private let wordmark=NSTextField(labelWithString:"sisu")
    private let field=RoundedField()
    private var searchButton:ChromeButton!
    private var shortcuts: [SiteShortcut] = []
    private var shortcutButtons: [ChromeButton] = []
    init(controller:BrowserWindow){
        self.controller=controller;super.init(frame:.zero)
        searchButton=ChromeButton(title:"Search",target:self,action:#selector(search))
        searchButton.selectedStyle=true;searchButton.setAccessibilityLabel("Search")
        field.isSearchField=true;field.rightPadding=108;field.font=NSFont(name:"Arial",size:15)
        field.target=self;field.action = #selector(search);field.setAccessibilityLabel("New tab search")
        addSubview(wallpaper);addSubview(wordmark);addSubview(field);addSubview(searchButton);updateProvider()
        if !controller.profile.isPrivate {
            shortcuts = SiteShortcut.load(in: controller.profile.root)
            shortcutButtons = shortcuts.enumerated().map { index, shortcut in
                let button = ChromeButton(title: shortcut.title, target: self, action: #selector(openShortcut(_:)))
                button.tag = index
                button.outlined = true
                button.font = NSFont(name: "Arial", size: 13)
                button.lineBreakMode = .byTruncatingTail
                button.toolTip = shortcut.url.absoluteString
                button.setAccessibilityLabel(shortcut.title)
                addSubview(button)
                return button
            }
        }
    }
    required init?(coder:NSCoder){fatalError()}
    func updateProvider(){field.placeholderString="Search with " + (controller?.profile.preferences.google == true ? "Google":"DuckDuckGo")}
    override func layout(){
        super.layout()
        wallpaper.frame = bounds
        let width=min(584,bounds.width*0.84),size=min(88,max(62,bounds.width*0.09))
        let columns = width >= 440 ? 4 : 3
        let rows = (shortcutButtons.count + columns - 1) / columns
        let shortcutHeight: CGFloat = rows == 0 ? 0 : 12 + CGFloat(rows) * 36
        let top=max(16,(bounds.height-(size+38+58+shortcutHeight))/2-bounds.height*0.04)
        wordmark.frame=NSRect(x:0,y:top,width:bounds.width,height:size+8)
        field.frame=NSRect(x:(bounds.width-width)/2,y:top+size+38,width:width,height:58)
        searchButton.frame=NSRect(x:field.frame.maxX-89,y:field.frame.minY+6,width:83,height:46)
        let shortcutWidth = (width - CGFloat(columns - 1) * 8) / CGFloat(columns)
        for (index, button) in shortcutButtons.enumerated() {
            let x = field.frame.minX + CGFloat(index % columns) * (shortcutWidth + 8)
            let y = field.frame.maxY + 16 + CGFloat(index / columns) * 36
            button.frame = NSRect(x: x, y: y, width: shortcutWidth, height: 29)
        }
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
    @objc private func openShortcut(_ sender: NSButton) {
        controller?.navigate(shortcuts[sender.tag].url.absoluteString)
    }
}

