-- Super Secret Settings — silly, purely-visual post-process filters unlocked by
-- the Konami code (like Minecraft's secret shaders). Order MATTERS: the array
-- index (0-based) is the slot used by the shader's fx[] uniform in main.lua.
return {
    { id = "invert",     name = "Inverted",     desc = "Negative-world vision." },
    { id = "grayscale",  name = "Noir",         desc = "Black & white drama." },
    { id = "sepia",      name = "Old Photo",    desc = "Aged sepia tones." },
    { id = "rainbow",    name = "Acid Trip",    desc = "Hue cycles forever." },
    { id = "thermal",    name = "Predator",     desc = "Thermal heat-vision." },
    { id = "pixelate",   name = "Lo-Res",       desc = "Crunchy big pixels." },
    { id = "crt",        name = "Old TV",       desc = "CRT scanlines + vignette." },
    { id = "wobble",     name = "Seasick",      desc = "The whole sea wobbles." },
    { id = "bloom",      name = "Too Much Glow",desc = "Everything overglows." },
    { id = "vaporwave",  name = "Vaporwave",    desc = "Aesthetic pink haze." },
    { id = "mirror",     name = "Mirror Mode",  desc = "Flip the world left-right." },
    { id = "upsidedown", name = "Down Under",   desc = "Everything's upside down." },
    { id = "nightvision",name = "Night Vision", desc = "Glowing green goggles." },
    { id = "chroma",     name = "3D Glasses",   desc = "RGB chromatic split." },
}
