#!/bin/sh

base="hdrezka.website"
images_cache_dir="/tmp/rezka-images"
[ -d "$images_cache_dir" ] || mkdir -p "$images_cache_dir"
preview_window_size="50%"

cleanup() {
    rm -rf "$images_cache_dir"
    ueberzug cmd -s "$REZKA_UEBERZUG_SOCKET" -a exit >/dev/null 2>&1
}
trap cleanup HUP INT QUIT TERM EXIT

command -v "ueberzugpp" >/dev/null || send_notification "Please install ueberzugpp if you want to use image preview with fzf"
ueberzug_x=$(($(tput cols) / 2 + 14))
ueberzug_y=$(($(tput lines) / 2 - 15))
ueberzug_max_width=$(($(tput cols) - 2))
ueberzug_max_height=$(($(tput lines) - 2))
ueberzug_output="sixel"

case "$(uname -s)" in
    MINGW* | *Msys) separator=';' && path_thing='' ;;
    *arwin) UEBERZUG_TMP_DIR="$TMPDIR" ;;
    *) separator=':' && path_thing="\\" && UEBERZUG_TMP_DIR="/tmp" ;;
esac

download_thumbnails() {
    printf "%s\n" "$1" | while read -r cover_url id type title; do
        cover_url=$(printf "%s" "$cover_url" | sed -E 's/\/[[:digit:]]+x[[:digit:]]+\//\/1000x1000\//')
        curl -s -o "$images_cache_dir/  $title ($type)  $id.jpg" "$cover_url" &
    done
    sleep "$2"
}

upscale_images() {
    printf "%s\n" "$1"/* | while read -r image; do convert "$image" -resize "$2x$3" "$image" & done
}

image_preview_fzf() {
    UB_PID_FILE="$UEBERZUG_TMP_DIR/.$(uuidgen)"
    ueberzugpp layer -o "$ueberzug_output" --no-stdin --silent --use-escape-codes --pid-file "$UB_PID_FILE"
    UB_PID="$(cat "$UB_PID_FILE")"
    REZKA_UEBERZUG_SOCKET=$UEBERZUG_TMP_DIR/ueberzugpp-"$UB_PID".socket
    choice=$(find "$images_cache_dir" -type f -exec basename {} \; | fzf -i -q "$1" --cycle --preview-window="$preview_window_size" --preview="ueberzugpp cmd -s $REZKA_UEBERZUG_SOCKET -i fzfpreview -a add -x $ueberzug_x -y $ueberzug_y --max-width $ueberzug_max_width --max-height $ueberzug_max_height -f $images_cache_dir/{}" --reverse --with-nth 2 -d "  ")
    ueberzugpp cmd -s "$REZKA_UEBERZUG_SOCKET" -a exit
}

hdrezka_data_and_translation_id() {
    data_id=$(printf "%s" "$media_id" | sed -nE "s@[a-z]*/([0-9]*)-.*@\1@p")
    case "$media_type" in
        films)
            default_translator_id=$(curl -s "https://${base}/${media_type}/$(printf "%s" "$media_id" | tr '=' '/').html" -A "uwu" --compressed |
                sed -nE "s@.*initCDNMoviesEvents\(${data_id}\, ([0-9]*)\,.*@\1@p")
            ;;
        *)
            default_translator_id=$(curl -s "https://${base}/${media_type}/$(printf "%s" "$media_id" | tr '=' '/').html" -A "uwu" --compressed |
                sed -nE "s@.*initCDNSeriesEvents\(${data_id}\, ([0-9]*)\,.*@\1@p")
            ;;
    esac
    translations=$(curl -s "https://${base}/${media_type}/$(printf "%s" "$media_id" | tr '=' '/').html" -A "uwu" --compressed |
        sed 's/b-translator__item/\n/g' | sed -nE "s@.*data-translator_id=\"([0-9]*)\"[^>]*>(.*)</li.*@\2\t\1@p" |
        sed 's/<img title="\([^\"]*\)" .*>\(.*\)/(\1)\2/;s/^\(.*\)<\/li><\/ul> <\/div>.*\t\([0-9]*\)/\1\t\2/')
    if [ -z "$translations" ]; then
        translator_id=$default_translator_id
    else
        translator_id=$(printf "%s" "$translations" | fzf --cycle --reverse --with-nth 1 -d "\t" --header "Choose a translation" | cut -f2)
    fi
}

[ -z "$*" ] && printf '\033[1;35m=> ' && read -r user_query || user_query=$*
[ -z "$user_query" ] && exit 1
query=$(printf "%s" "$user_query" | tr " " "+")

request=$(curl -s "https://${base}/search/?do=search&subaction=search&q=${query}" -A "uwu" --compressed)
response=$(printf "%s" "$request" | sed "s/<img/\n/g" | sed -nE "s@.*src=\"([^\"]*)\".*<a href=\"https://hdrezka\.website/(.*)/(.*)/(.*)\.html\">([^<]*)</a> <div>([0-9]*).*@\1\t\3=\4\t\2\t\5 [\6]@p")
[ -z "$response" ] && exit 1
download_thumbnails "$response" "1"
upscale_images "$images_cache_dir" "1000" "1000"
image_preview_fzf ""
title=$(printf "%s" "$choice" | sed -nE "s@[[:space:]]{2}(.*) \((films|series|cartoons|animation)\).*@\1@p")
media_type=$(printf "%s" "$choice" | sed -nE "s@[[:space:]]{2}(.*) \((films|series|cartoons|animation)\).*@\2@p")
media_id=$(printf "%s" "$choice" | sed -nE "s@[[:space:]]{2}(.*) \((films|series|cartoons|animation)\)[[:space:]]{2}(.*)\.jpg@\3@p" | tr '=' '/')
[ -z "$media_id" ] && exit 1
[ -z "$title" ] && exit 1

hdrezka_data_and_translation_id
tmp_season_id=$(curl -s "https://${base}/${media_type}/${media_id}.html" -A "uwu" --compressed | sed "s/<li/\n/g" |
    sed -nE "s@.*data-tab_id=\"([0-9]*)\">([^<]*)</li>.*@\2\t\1@p")
if [ -n "$tmp_season_id" ]; then
    tmp_season_id=$(printf "%s" "$tmp_season_id" | fzf -1 --cycle --reverse --with-nth 1 -d '\t' --header "Choose a season: ")
    [ -z "$tmp_season_id" ] && exit 1
    season_title=$(printf "%s" "$tmp_season_id" | cut -f1)
    season_id=$(printf "%s" "$tmp_season_id" | cut -f2)
    episode_id=$(curl -s -X POST "https://${base}/ajax/get_cdn_series/" -A "uwu" --data-raw "id=${data_id}&translator_id=${translator_id}&season=${season_id}&action=get_episodes" --compressed |
        sed "s/\\\//g;s/cdn_url/\n/g" |
        sed -nE "s@.*data-season_id=\"${season_id}\" data-episode_id=\"([0-9]*)\".*@\1@p" | fzf --cycle --reverse --header "Chooses an episode: ")
    [ -z "$episode_id" ] && exit 1
fi

case "$media_type" in
    series | cartoons) json_data=$(curl -s -X POST "https://${base}/ajax/get_cdn_series/" -A "uwu" --data-raw "id=${data_id}&translator_id=${translator_id}&season=${season_id}&episode=${episode_id}&action=get_stream" --compressed) ;;
    *) json_data=$(curl -s -X POST "https://${base}/ajax/get_cdn_series/" -A "uwu" --data-raw "id=${data_id}&translator_id=${translator_id}&action=get_movie" --compressed) ;;
esac
[ -z "$json_data" ] && exit 1

encrypted_video_link=$(printf "%s" "$json_data" | sed -nE "s@.*\"url\":\"([^\"]*)\".*@\1@p" | sed "s/\\\//g" | cut -c'3-' | sed 's|//_//||g')
# the part below is pain
subs_links=$(printf "%s" "$json_data" | sed -nE "s@.*\"subtitle\":\"([^\"]*)\".*@\1@p" |
    sed -e 's/\[[^]]*\]//g' -e 's/,/\n/g' -e 's/\\//g' -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
# TODO: fix subs
subs_arg="--sub-files=$subs_links"

# ty @CoolnsX for helping me out with the decryption
table='ISE=,IUA=,IV4=,ISM=,ISQ=,QCE=,QEA=,QF4=,QCM=,QCQ=,XiE=,XkA=,Xl4=,XiM=,XiQ=,IyE=,I0A=,I14=,IyM=,IyQ=,JCE=,JEA=,JF4=,JCM=,JCQ=,ISEh,ISFA,ISFe,ISEj,ISEk,IUAh,IUBA,IUBe,IUAj,IUAk,IV4h,IV5A,IV5e,IV4j,IV4k,ISMh,ISNA,ISNe,ISMj,ISMk,ISQh,ISRA,ISRe,ISQj,ISQk,QCEh,QCFA,QCFe,QCEj,QCEk,QEAh,QEBA,QEBe,QEAj,QEAk,QF4h,QF5A,QF5e,QF4j,QF4k,QCMh,QCNA,QCNe,QCMj,QCMk,QCQh,QCRA,QCRe,QCQj,QCQk,XiEh,XiFA,XiFe,XiEj,XiEk,XkAh,XkBA,XkBe,XkAj,XkAk,Xl4h,Xl5A,Xl5e,Xl4j,Xl4k,XiMh,XiNA,XiNe,XiMj,XiMk,XiQh,XiRA,XiRe,XiQj,XiQk,IyEh,IyFA,IyFe,IyEj,IyEk,I0Ah,I0BA,I0Be,I0Aj,I0Ak,I14h,I15A,I15e,I14j,I14k,IyMh,IyNA,IyNe,IyMj,IyMk,IyQh,IyRA,IyRe,IyQj,IyQk,JCEh,JCFA,JCFe,JCEj,JCEk,JEAh,JEBA,JEBe,JEAj,JEAk,JF4h,JF5A,JF5e,JF4j,JF4k,JCMh,JCNA,JCNe,JCMj,JCMk,JCQh,JCRA,JCRe,JCQj,JCQk'

for i in $(printf "%s" "$table" | tr ',' '\n'); do
    encrypted_video_link=$(printf "%s" "$encrypted_video_link" | sed "s/$i//g")
done

video_links=$(printf "%s" "$encrypted_video_link" | sed 's/_//g' | base64 -d | tr ',' '\n' | sed -nE "s@\[([^\]*)\](.*)@\"\1\":\"\2\",@p")
video_links_json=$(printf "%s" "$video_links" | tr -d '\n' | sed "s/,$//g")
json_data=$(printf "%s" "$json_data" | sed -E "s@\"url\":\"[^\"]*\"@\"url\":\{$video_links_json\}@")

if [ -n "$quality" ]; then
    video_link=$(printf "%s" "$video_links" | sed -nE "s@\"${quality}.*\":\".* or ([^\"]*)\".*@\1@p" | tail -1)
else
    # auto selects best quality
    video_link=$(printf "%s" "$video_links" | sed -nE "s@\".*\":\".* or ([^\"]*)\".*@\1@p" | tail -1)
fi
[ -z "$video_link" ] && exit 1
if [ "$media_type" = "tv" ] || [ "$media_type" = "series" ] || [ "$media_type" = "cartoons" ]; then
    displayed_title="$title - $season_title - $episode_id"
else
    displayed_title="$title"
fi
mpv --force-media-title="$displayed_title" "$video_link"
