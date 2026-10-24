import AppKit

// Original vector artwork. No game artwork or downloaded imagery is used.
// Run from the package root: swift script/generate_app_icon.swift
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets", isDirectory: true)
let iconset = assets.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func polygon(_ points: [NSPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: points[0])
    points.dropFirst().forEach { path.line(to: $0) }
    path.close()
    return path
}

func artwork(size: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 198, yRadius: 198)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow();shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 24;shadow.shadowOffset = NSSize(width: 0,height: -12);shadow.set()
    NSColor.systemPurple.setFill();tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colorsAndLocations:
        (NSColor(calibratedRed: 0.37,green: 0.36,blue: 1,alpha: 1),0),
        (NSColor(calibratedRed: 0.73,green: 0.23,blue: 0.98,alpha: 1),0.5),
        (NSColor(calibratedRed: 0.96,green: 0.16,blue: 0.53,alpha: 1),1))!
        .draw(in: tile,angle: -42)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let sheen = NSBezierPath(ovalIn: NSRect(x: -80,y: 610,width: 1180,height: 550))
    NSGradient(starting: .white.withAlphaComponent(0.24),ending: .white.withAlphaComponent(0))!
        .draw(in: sheen,angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.32).setStroke();tile.lineWidth = 2;tile.stroke()

    // Three layered isometric plots echo the studio's existing layered mark.
    let lower = polygon([NSPoint(x: 240,y: 367),NSPoint(x: 512,y: 222),NSPoint(x: 784,y: 367),
                         NSPoint(x: 784,y: 326),NSPoint(x: 512,y: 178),NSPoint(x: 240,y: 326)])
    NSColor.white.withAlphaComponent(0.65).setFill();lower.fill()
    let middle = polygon([NSPoint(x: 240,y: 449),NSPoint(x: 512,y: 304),NSPoint(x: 784,y: 449),
                          NSPoint(x: 784,y: 408),NSPoint(x: 512,y: 260),NSPoint(x: 240,y: 408)])
    NSColor.white.withAlphaComponent(0.86).setFill();middle.fill()
    let land = polygon([NSPoint(x: 236,y: 514),NSPoint(x: 512,y: 664),NSPoint(x: 788,y: 514),NSPoint(x: 512,y: 362)])
    NSGraphicsContext.saveGraphicsState()
    let liftedShadow = NSShadow();liftedShadow.shadowBlurRadius = 24
    liftedShadow.shadowOffset = NSSize(width: 0,height: -10)
    liftedShadow.shadowColor = NSColor(calibratedRed: 0.23,green: 0.06,blue: 0.55,alpha: 0.3)
    liftedShadow.set();NSColor.white.setFill();land.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.93,green: 1,blue: 1,alpha: 1),ending: .white)!
        .draw(in: land,angle: -90)

    // A small architectural home rises from the plot, with a luminous window.
    let leftWall = polygon([NSPoint(x: 386,y: 562),NSPoint(x: 512,y: 491),NSPoint(x: 512,y: 664),NSPoint(x: 386,y: 733)])
    NSColor(calibratedRed: 0.82,green: 0.76,blue: 1,alpha: 1).setFill();leftWall.fill()
    let rightWall = polygon([NSPoint(x: 512,y: 491),NSPoint(x: 656,y: 571),NSPoint(x: 656,y: 744),NSPoint(x: 512,y: 664)])
    NSColor.white.setFill();rightWall.fill()
    let roof = polygon([NSPoint(x: 348,y: 735),NSPoint(x: 491,y: 815),NSPoint(x: 696,y: 745),
                        NSPoint(x: 552,y: 663)])
    NSGradient(starting: .white,ending: NSColor(calibratedRed: 0.84,green: 0.87,blue: 1,alpha: 1))!
        .draw(in: roof,angle: -45)
    let window = polygon([NSPoint(x: 551,y: 552),NSPoint(x: 614,y: 587),NSPoint(x: 614,y: 679),NSPoint(x: 551,y: 644)])
    NSGradient(starting: NSColor(calibratedRed: 0.16,green: 0.92,blue: 0.89,alpha: 1),
               ending: NSColor(calibratedRed: 0.24,green: 0.65,blue: 1,alpha: 1))!
        .draw(in: window,angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

for base in [16,32,128,256,512] {
    for scale in [1,2] {
        let size = base*scale
        let filename = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try artwork(size: size).representation(using: .png,properties: [:])!
            .write(to: iconset.appendingPathComponent(filename))
    }
}
try artwork(size: 1024).representation(using: .png,properties: [:])!
    .write(to: assets.appendingPathComponent("AppIcon.png"))
let task = Process();task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c","icns",iconset.path,"-o",assets.appendingPathComponent("AppIcon.icns").path]
try task.run();task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("App icon packaging failed") }
print("Saved original AppIcon.png, AppIcon.iconset and AppIcon.icns in Assets")
