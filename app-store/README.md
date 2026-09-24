# App Store assets

English (US) description: `description.txt`.

Screenshots in `screenshots/iphone-6.5/` are unscaled simulator captures at 1242 × 2688, RGB PNG without alpha. Device: iPhone 11 Pro Max; runtime: iOS 26.5. Source: a57492c2655a27603f7d4210d05505cbea1668e2, plus the icon-only configuration changes in this commit.

Order: 01 garment registry; 02 recorded care details; 03 wash-symbol reference. The blue cotton shirt is illustrative sample data.

To reproduce: build the CareLabel scheme for an iPhone 11 Pro Max simulator. Add “Blue cotton shirt” as a Top, set Wash to Machine wash (40 °C, normal), and save. Capture the registry, open the garment and capture its details, then Edit → Symbol reference — Wash and capture the reference. Set the simulator status bar to 9:41 before capture. Use `xcrun simctl io <device-id> screenshot <file.png>` and export without alpha, preserving the native dimensions.

The custom AppIcon is installed in `App/Assets.xcassets/AppIcon.appiconset`. It is 1024 × 1024 RGB PNG, fully opaque, with square edge-to-edge artwork. Created with the built-in image-generation tool: folded cream cotton garment with a blank care tag and water-droplet motif over a teal-to-seafoam gradient and flowing fabric, no text, borders or rounded corners.

No App Store upload or submission is performed by this commit.
