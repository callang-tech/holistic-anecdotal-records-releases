# Bundled branding

`app_logo.png` is the approved application logo. `school.jpg` is the real
Callang National High School photograph. Both are developer-controlled assets;
updates ship by replacing the bundled files and rebuilding the application.
Do not add user replacement controls, persisted replacement paths, or external
file overrides for either image. Crop the school photograph only in layout.

`project_leader.jpg` is Michelle A. Carpio, RGC's approved System Leadership
portrait. It follows the same developer-controlled, bundled-only policy.
Preserve the original file; apply responsive cropping only in Flutter layout.
Joven Danipog receives text-only credit in Acknowledgements, without a portrait.

The Windows executable and window use `windows/runner/resources/app_icon.ico`.
Installer branding uses the same icon; shortcuts use the executable's icon.
After an approved logo update, regenerate the icon from the project root with
Python and Pillow, preserving the source artwork:

```powershell
python -c "from PIL import Image; Image.open('assets/images/about/app_logo.png').save('windows/runner/resources/app_icon.ico', format='ICO', sizes=[(n,n) for n in (16,24,32,48,64,128,256)])"
```

Rebuild the Windows release and installer to distribute the updated branding.
