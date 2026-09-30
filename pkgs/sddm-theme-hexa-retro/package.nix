{ lib, runCommand, imagemagick, adi1090x-plymouth-themes }:
let
  plymouthThemes = adi1090x-plymouth-themes.override {
    selected_themes = [ "hexa_retro" ];
  };
  frames = "${plymouthThemes}/share/plymouth/themes/hexa_retro";
in
runCommand "sddm-theme-hexa-retro" {
  nativeBuildInputs = [ imagemagick ];
  meta = {
    description = "SDDM theme matching the hexa_retro Plymouth animation";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
} ''
  dir=$out/share/sddm/themes/hexa_retro
  mkdir -p $dir
  list=""
  for i in $(seq 0 89); do
    list="$list ${frames}/progress-$i.png"
  done
  magick -delay 4 $list -resize 300x300 -loop 0 -layers optimize \
    $dir/hexa_retro.gif
  cp ${./Main.qml} $dir/Main.qml
  cp ${./metadata.desktop} $dir/metadata.desktop
''
