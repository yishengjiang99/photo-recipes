import Foundation

/// Faithful port of `src/data/presets.ts` — do not invent recipes beyond these ten.
enum BundledPresets {
    static let all: [Recipe] = [
        leadingLines,
        minimalistPhotos,
        exposureTriangleCheatsheet,
        sharpAndInFocus,
        portraitPop,
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

    // MARK: - Page 12

    static let leadingLines = Recipe(
        id: "leading-lines",
        page: 12,
        title: "Point to Your Main Subject With Leading Lines",
        blurb: "Pull the viewer's eye from the foreground into the background — rock formations, branches, waves, light and shadows.",
        whenToUse: "Any landscape or scene where you can find a naturally occurring line — or a series of parallel lines — to aim at your main subject. Curved leading lines are the best.",
        tags: [.composition],
        gear: [.camera, .phone],
        dials: DialSettings(
            mode: .auto,
            notes: "Composition over exposure settings; deep focus helps."
        ),
        steps: [
            "Search for a naturally occurring line or series of parallel lines. Use any and all aspects of the landscape.",
            "Position yourself so the lines will emerge out of the foreground of your image.",
            "Avoid lines that run out of your photo on the side. The viewer's eye will leave with it.",
            "Your leading lines should point towards the main subject.",
        ],
        tips: [
            "A leading line can be rock formations, trees reaching to the sky, branches, breaking waves, or even light and shadows.",
            "Curved leading lines are the best.",
            "Lines should start in the foreground and point at the subject — never let them run out the side.",
        ],
        equipmentChecklist: [
            "Camera or phone",
            "Rule-of-thirds grid on",
        ],
        phoneTip: "Turn on the rule-of-thirds grid and place the subject where a leading line meets a third line."
    )

    // MARK: - Page 16

    static let minimalistPhotos = Recipe(
        id: "minimalist-photos",
        page: 16,
        title: "Minimalist Photos Win the Awards",
        blurb: "Simple, uncluttered, non-busy images that convey one simple message — the kind that wins photo contests.",
        whenToUse: "When you find one simple thing that stands out from its surroundings — a lone tree on a horizon line, a single shape in fog. Best in gloomy weather or the blue hour.",
        tags: [.composition],
        gear: [.camera, .phone],
        dials: DialSettings(
            mode: .auto,
            notes: "Expose for the mood; underexpose slightly at blue hour."
        ),
        steps: [
            "Search for one simple thing that stands out from its surroundings. Non-busy surroundings are the best.",
            "Use the rule of thirds: place the main subject on a third line. If the subject faces one direction, have it face into, and not out of, your photo.",
            "Use weather to your advantage. Minimalist photos look great in gloomy weather or when the light is low during the blue hour (the 30 minutes after the sun sets).",
        ],
        tips: [
            "One subject, one message — remove everything else from the frame.",
            "A single tree on a horizon line with nothing behind it is the classic.",
            "Blue hour (30 minutes after sunset) gives low, moody light.",
            "If the subject faces a direction, leave space in front of it.",
        ],
        equipmentChecklist: [
            "Camera or phone",
            "Rule-of-thirds grid on",
        ]
    )

    // MARK: - Page 20

    static let exposureTriangleCheatsheet = Recipe(
        id: "exposure-triangle-cheatsheet",
        page: 20,
        title: "The Camera Settings Cheat Sheet",
        blurb: "The exposure triangle on one card: aperture, ISO, and shutter speed — change one, compensate with another.",
        whenToUse: "Reference card for any shoot. Read before you touch the dials: understand what each setting does so you can leave auto mode behind.",
        tags: [],
        gear: [.camera],
        dials: DialSettings(
            mode: .auto,
            notes: "Reference card — no single dial setting; it explains the triangle."
        ),
        steps: [
            "There are three essential settings you can adjust: ISO, shutter speed, and aperture. If you change one, you will need to compensate by changing another.",
            "If you use auto mode, your camera is making all these decisions for you. Don't use auto mode. You are not a beginner. You have this book.",
        ],
        tips: [
            "Aperture f/22 → f/2.8: small aperture keeps the image darker with deep focus; large aperture brightens it with shallow focus.",
            "ISO 100 → 4000: adds \"fake light\" to a dark image, but too much ISO introduces noise (graininess).",
            "Shutter 1/1000 → 1/30: fast speeds darken the image and freeze motion; slow speeds brighten it and blur motion.",
        ],
        equipmentChecklist: [
            "Camera",
            "This card",
        ],
        subVariants: [
            SubVariant(
                id: "cheatsheet-aperture",
                label: "Aperture",
                description: "Controls how much of your scene is in focus.",
                dials: DialSettings(
                    mode: .aperturePriority,
                    aperture: "small f-stop → shallow focus",
                    notes: "Sharp foreground + blurred background: use a small f-stop number."
                ),
                tips: [
                    "Small f-stop number = blurred background, subject pops.",
                    "Large f-stop number = more of the scene in focus.",
                ]
            ),
            SubVariant(
                id: "cheatsheet-iso",
                label: "ISO",
                description: "Sensor sensitivity — \"fake light\" with a noise cost.",
                dials: DialSettings(
                    mode: .manual,
                    iso: "as low as the light allows",
                    notes: "Raise ISO to brighten a dark image; watch for graininess."
                ),
                tips: [
                    "ISO 100 in sun, 160–400 in shade, 1600+ at night.",
                    "Increasing ISO too much introduces noise into the image.",
                ]
            ),
            SubVariant(
                id: "cheatsheet-shutter",
                label: "Shutter speed",
                description: "How long the sensor sees light — freezes or blurs motion.",
                dials: DialSettings(
                    mode: .shutterPriority,
                    shutter: "1/1000 freeze → 1/30 blur",
                    notes: "Fast darkens; slow brightens."
                ),
                tips: [
                    "Fast shutter (1/1000) darkens the image and freezes motion.",
                    "Slow shutter (1/30) brightens the image and blurs motion.",
                ]
            ),
        ]
    )

    // MARK: - Page 24

    static let sharpAndInFocus = Recipe(
        id: "sharp-and-in-focus",
        page: 24,
        title: "Sharp and in Focus",
        blurb: "Take control of focus: turn off multi-point, put a single focus point exactly where it matters — on the eyes.",
        whenToUse: "Portraits, pets, wildlife, any subject where the camera's multi-point focus might pick the wrong element. You are smarter than the camera.",
        tags: [.depthOfField],
        gear: [.camera, .phone],
        dials: DialSettings(
            mode: .aperturePriority,
            aperture: "high f-stop for more in focus",
            notes: "Single-point focus; high f-stop trades light for depth of field (see cheat sheet, page 20)."
        ),
        steps: [
            "On a phone camera, you can tap the element to be used as the focus point. On a camera, turn on single point focus (google your camera's model to learn how to do this).",
            "Determine exactly what element in the frame needs to be sharp. If your subject is a person or animal, choose the eyes. Set the focus point on them.",
            "Use your aperture to set the desired amount of depth of field. A high f-stop number will result in more elements being in sharp focus, but there are trade offs that come with that. See the camera settings cheat sheet on page 20.",
        ],
        tips: [
            "Multi-point focus lets the camera guess — single-point focus lets you decide.",
            "For people and animals, always focus on the eyes.",
            "Zoom in tight after the shot to verify the face is truly sharp.",
        ],
        equipmentChecklist: [
            "Camera or phone",
        ],
        phoneTip: "Tap the element on your phone screen to set the focus point exactly where you want it."
    )

    // MARK: - Page 26

    static let portraitPop = Recipe(
        id: "portrait-pop",
        page: 26,
        title: "Make a Portrait Pop by Blurring the Background",
        blurb: "Blur the background so distractions melt away and the subject pops off the screen.",
        whenToUse: "Portraits of people (or pets) where the background competes with the subject. Widest aperture + zoom + eye focus.",
        tags: [.depthOfField],
        gear: [.camera, .phone],
        dials: DialSettings(
            mode: .aperturePriority,
            aperture: "smallest f-stop (wide open)",
            notes: "Widest aperture + most zoom + single-point focus on the eyes."
        ),
        steps: [
            "Use aperture priority mode with the camera's smallest f-stop number.",
            "To magnify the effect even more, use the most possible zoom on your lens.",
            "Use single point focus and be sure to focus on one of the eyes.",
            "Take the photo and zoom in tight on the image to ensure the face is fully in focus. It is easy for the face to come out with a soft focus, and you don't want that.",
        ],
        tips: [
            "Smallest f-stop number = most background blur.",
            "More zoom = stronger blur effect.",
            "Focus on the eyes — soft-focus faces ruin the shot.",
            "After shooting, zoom in tight to verify the face is fully sharp.",
        ],
        equipmentChecklist: [
            "Camera or phone",
        ],
        phoneTip: "Cell phone cameras often have a portrait mode that will help create this effect."
    )

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
