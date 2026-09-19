import Foundation

/// Faithful port of `src/data/presets.ts` — do not invent recipes beyond these five.
enum BundledPresets {
    static let all: [Recipe] = [
        sharpFrontToBack,
        blurMovingSubjects,
        panningSharpSubject,
        getDownLow,
        hdrBrightsDarks,
    ]

    static func recipe(id: String) -> Recipe? {
        all.first { $0.id == id }
    }

    static let allTags: [TechniqueTag] = TechniqueTag.allCases

    // MARK: - Page 28

    static let sharpFrontToBack = Recipe(
        id: "sharp-front-to-back",
        page: 28,
        title: "Sharp from Front to Back",
        blurb: "Plan maximum depth of field so everything from foreground rocks to distant skyline stays sharp.",
        whenToUse: "Landscapes and scenes that must be sharp from the near foreground all the way to the background. Plan ahead so you are not disappointed when you review at home.",
        tags: [.depthOfField],
        gear: [.camera, .phone, .tripod, .flash],
        dials: DialSettings(
            mode: .aperturePriority,
            aperture: "f/11–f/16",
            shutter: "auto (tripod if <1/200s)",
            iso: "as needed",
            notes: "Do not go above f/16 — diffraction softens the image."
        ),
        steps: [
            "Use aperture priority with a high f-stop number to get the longest possible depth of field. Try not to go above f/16 because a softness called diffraction will be introduced into the image.",
            "Use single-point focus and focus on an object that is about one third into your frame. This is the simplest way of using hyperfocal distance for maximum sharpness front to back.",
            "Because the aperture value is high, this darkens the image. Your camera will compensate by setting a long shutter speed — use a tripod if the shutter speed is slower than 1/200 of a second.",
        ],
        tips: [
            "Stay at or below f/16 to avoid diffraction softness.",
            "Focus about ⅓ into the frame (hyperfocal shortcut).",
            "Tripod when shutter drops below 1/200s.",
        ],
        equipmentChecklist: [
            "Camera or phone",
            "Tripod (if shutter < 1/200s)",
            "Stable footing / level horizon",
        ]
    )

    // MARK: - Page 30

    static let blurMovingSubjects = Recipe(
        id: "blur-moving-subjects",
        page: 30,
        title: "How to Blur Moving Subjects",
        blurb: "Show motion with intentional blur — daytime water and people, or night light trails from traffic.",
        whenToUse: "Daytime: blur a moving object (person, car, waterfall, waves) to show motion. Night: light trails from cars or someone waving a flashlight.",
        tags: [.motion],
        gear: [.camera, .tripod, .remote],
        dials: DialSettings(
            mode: .shutterPriority,
            aperture: "auto",
            shutter: "1/2s (day) · 20s (night)",
            iso: "low",
            notes: "Always use a tripod. Remote at night to prevent shake."
        ),
        steps: [
            "Mount the camera on a tripod. Use shutter priority.",
            "For daytime motion: start around 1/2 sec for a running person, moving car, or waterfall; try ~1/3 sec for waves retreating on a beach.",
            "Do not extend the shutter for too long or all detail will be lost — experiment to find the optimum speed.",
            "For night light trails: use shutter priority, tripod, and a remote shutter release. Around 20 seconds is common.",
            "Be prepared to take many photos and adjust shutter speed based on the results you are seeing.",
        ],
        tips: [
            "Tripod is essential for clean blur without camera shake.",
            "Remote release for night shots prevents shake from pressing the shutter.",
            "Too long a daytime exposure loses all subject detail.",
        ],
        equipmentChecklist: [
            "Camera",
            "Tripod",
            "Remote shutter release (especially at night)",
        ],
        subVariants: [
            SubVariant(
                id: "daytime-blur",
                label: "Daytime motion blur",
                description: "Blur a moving object — people, cars, waterfalls, or beach waves — during the day.",
                dials: DialSettings(
                    mode: .shutterPriority,
                    aperture: "auto",
                    shutter: "1/2s · waves ~1/3s",
                    iso: "low"
                ),
                tips: [
                    "1/2 sec works well for a running person, moving car, or waterfall.",
                    "1/3 sec is good for waves on a beach retreating toward the ocean.",
                    "Do not extend the shutter too long or all details will be lost.",
                ]
            ),
            SubVariant(
                id: "night-light-trails",
                label: "Night light trails",
                description: "Capture light trails from moving cars or someone waving a flashlight.",
                dials: DialSettings(
                    mode: .shutterPriority,
                    aperture: "auto",
                    shutter: "~20s",
                    iso: "low"
                ),
                tips: [
                    "20 seconds is common for catching light trails.",
                    "Use a remote shutter release to prevent camera shake.",
                    "Take many frames and adjust shutter based on results.",
                ]
            ),
        ]
    )

    // MARK: - Page 32

    static let panningSharpSubject = Recipe(
        id: "panning-sharp-subject",
        page: 32,
        title: "Keep a Moving Subject Sharp, With Motion Blur in the Background",
        blurb: "Pan with your subject so they stay sharp while the background streaks — best tried in daylight.",
        whenToUse: "Any moving subject you want sharp against a blurred background that shows motion. Best during daylight.",
        tags: [.motion],
        gear: [.camera, .flash],
        dials: DialSettings(
            mode: .shutterPriority,
            aperture: "auto",
            shutter: "1/30s (start)",
            iso: "as needed",
            notes: "Rotate your body at the same speed as the subject."
        ),
        steps: [
            "Use shutter priority with a shutter speed of 1/30 sec as a starting point.",
            "Hold the camera in your hands and rotate your body at the same speed as the moving subject. Experiment with faster or slower shutter speeds. Review and make adjustments based on the results you are seeing.",
        ],
        tips: [
            "Start at 1/30s, then experiment faster/slower.",
            "Match your body rotation to the subject’s speed.",
            "Works best in daylight.",
        ],
        equipmentChecklist: [
            "Camera (hand-held for standard technique)",
            "Flash (for advanced rear-curtain method)",
            "Subject close enough for flash (advanced)",
        ],
        subVariants: [
            SubVariant(
                id: "panning-basic",
                label: "Basic panning",
                description: "Shutter priority daylight panning — subject sharp, background blurred.",
                dials: DialSettings(
                    mode: .shutterPriority,
                    aperture: "auto",
                    shutter: "1/30s"
                ),
                tips: [
                    "Start at 1/30 sec.",
                    "Rotate with the subject; review and adjust.",
                ]
            ),
            SubVariant(
                id: "panning-advanced-flash",
                label: "Advanced + rear curtain flash",
                description: "Manual mode, high f-stop, ~1/3s, flash with rear curtain sync for close subjects.",
                dials: DialSettings(
                    mode: .manual,
                    aperture: "high f-stop",
                    shutter: "1/3s",
                    notes: "Slightly dark exposure + on-camera flash, rear curtain sync."
                ),
                tips: [
                    "Darken with a high f-stop; image should look slightly dark.",
                    "Subject must be close to the flash.",
                    "Use rear curtain sync if available.",
                ]
            ),
        ],
        advancedTip: "Use manual mode and darken the scene with a high f-stop value. Try a shutter speed of 1/3 sec. The image should look slightly dark. Use a flash on the camera — this only works if the subject is close to the flash. Try the rear curtain sync flash setting if your camera has it."
    )

    // MARK: - Page 40

    static let getDownLow = Recipe(
        id: "get-down-low",
        page: 40,
        title: "Shake Up Your Perspective by Getting Down Low",
        blurb: "Shoot at knee-height with a wide angle so the foreground dominates — the wide-angle lens paradox.",
        whenToUse: "Whenever you always shoot at head-height and want a fresh composition. Think of what the scene would look like if you were the size of a small dog.",
        tags: [.composition],
        gear: [.camera, .phone, .wideAngle],
        dials: DialSettings(
            mode: .auto,
            aperture: "any",
            shutter: "any",
            notes: "Widest angle; composition over exposure settings."
        ),
        steps: [
            "Take a photo the usual way while standing. Assess the composition and move as necessary.",
            "Kneel down low and take the same photo at knee-height. Now compare both photos. Which one is better?",
        ],
        tips: [
            "Set the lens to its widest angle.",
            "Foreground becomes the main subject; background appears smaller.",
            "Phone tip: flip the phone upside down so the lens is on the bottom to get super low.",
        ],
        equipmentChecklist: [
            "Camera or phone",
            "Wide-angle lens (or phone ultra-wide)",
            "Willingness to kneel / get dirty",
        ],
        phoneTip: "If you are shooting with a phone, you can get super low by flipping your phone upside down, so the lens is on the bottom."
    )

    // MARK: - Page 44

    static let hdrBrightsDarks = Recipe(
        id: "hdr-brights-darks",
        page: 44,
        title: "Capture all the Brights and Darks With HDR",
        blurb: "High dynamic range for scenes with bright highlights and dark shadows — keep the result looking natural.",
        whenToUse: "Scenes with bright highlights and dark shadows — especially sunsets where you need to see a dark foreground. Process without an “HDR look.”",
        tags: [.hdr],
        gear: [.camera, .phone, .tripod, .flash],
        dials: DialSettings(
            mode: .aperturePriority,
            aperture: "locked (A/Av)",
            shutter: "bracketed",
            evBracket: "−2 / 0 / +2 EV",
            notes: "Tripod required. Combine in post; keep it natural."
        ),
        steps: [
            "Decide phone vs camera method (see tips below).",
            "Use a tripod so nothing moves between frames.",
            "Digital camera: turn on bracketing for three photos at −2 EV, 0 EV, and +2 EV. Use aperture priority.",
            "Check the histogram: on the brightest image the darks should be visible; on the darkest image highlights should not be blown out. Adjust with the EV button if needed.",
            "Combine the three images into one HDR photo in post. Don’t overprocess it — keep it looking natural.",
        ],
        tips: [
            "Phone: use the built-in HDR setting; keep the phone on a tripod.",
            "Camera: bracket −2 / 0 / +2 EV in aperture priority.",
            "Verify histograms on the brightest and darkest frames.",
            "Avoid the overcooked “HDR look.”",
        ],
        equipmentChecklist: [
            "Camera or phone",
            "Tripod",
            "Post-processing app/software for merging brackets",
        ],
        subVariants: [
            SubVariant(
                id: "hdr-phone",
                label: "Cell phone method",
                description: "Use the phone’s HDR setting with a tripod for a quick multi-shot merge.",
                dials: DialSettings(
                    mode: .phoneHdr,
                    shutter: "burst (auto)",
                    notes: "Tripod so the phone does not move."
                ),
                tips: [
                    "Enable HDR in the camera app.",
                    "Keep the phone still on a tripod during the burst.",
                ]
            ),
            SubVariant(
                id: "hdr-camera",
                label: "Digital camera method",
                description: "Tripod + exposure bracketing −2/0/+2 EV in aperture priority, merge in post.",
                dials: DialSettings(
                    mode: .aperturePriority,
                    aperture: "fixed across brackets",
                    evBracket: "−2 / 0 / +2 EV",
                    notes: "Check histograms; merge naturally in post."
                ),
                tips: [
                    "Three frames: −2, 0, +2 EV.",
                    "Brightest frame: darks visible. Darkest frame: highlights not blown.",
                    "Don’t overprocess the merge.",
                ]
            ),
        ],
        phoneTip: "Most phone cameras have an HDR setting in the camera app that will fire off a few photos very quickly. Use a tripod so your phone doesn’t move while the shots are being taken."
    )
}
