param([Parameter(Mandatory)][string]$Output, [string]$FFmpeg = $env:SHOTMAP_FFMPEG)

$ErrorActionPreference = 'Stop'
if (-not $FFmpeg) { $FFmpeg = (Get-Command ffmpeg.exe).Source }
$null = New-Item -ItemType Directory -Force -Path $Output
$Output = (Resolve-Path -LiteralPath $Output).Path

function Encode([string[]]$Arguments) {
    & $FFmpeg -hide_banner -loglevel error -nostdin -n @Arguments
    if ($LASTEXITCODE -ne 0) { throw "FFmpeg fixture generation failed ($LASTEXITCODE)." }
}

$font = 'C\:/Windows/Fonts/consola.ttf'
$test = 'testsrc2=s=640x360:r=10:d=8'
$markers = "hue=h=48*t,drawtext=fontfile='$font':text='%{n}':fontsize=52:fontcolor=white:box=1:boxcolor=black:x=(w-tw)/2:y=(h-th)/2,drawbox=x=0:y=0:w=60:h=60:color=red:t=fill,drawbox=x=iw-60:y=0:w=60:h=60:color=yellow:t=fill,drawbox=x=0:y=ih-60:w=60:h=60:color=blue:t=fill,drawbox=x=iw-60:y=ih-60:w=60:h=60:color=lime:t=fill"
$h264 = @('-c:v','libx264','-preset','veryfast','-threads','4','-pix_fmt','yuv420p')
$zh = -join [char[]](0x6D4B,0x8BD5,0x7D20,0x6750)
$media = Join-Path $Output "$zh 01"
$null = New-Item -ItemType Directory -Force -Path $media
$cfr = Join-Path $media "$zh H264.mp4"
$vfr = Join-Path $media "$zh VFR.mp4"
Encode (@('-f','lavfi','-i', $test, '-vf', $markers) + $h264 + @($cfr))
Encode (@('-f','lavfi','-i', $test, '-vf', "$markers,settb=1/1000,setpts='100+N*130+mod(N,4)*27'",
    '-fps_mode','vfr','-enc_time_base','1:1000','-video_track_timescale','1000') + $h264 + @('-g','100','-bf','2',$vfr))
Encode @('-display_rotation','90','-i',$vfr,'-c','copy',(Join-Path $media 'rotation VFR.mov'))
Encode @('-i',$cfr,'-c:v','libx265','-preset','ultrafast','-x265-params','pools=2:frame-threads=2:log-level=error',
    '-tag:v','hvc1',(Join-Path $media 'HEVC.mp4'))

$quality = @('-f','lavfi','-i','color=black:s=640x360:r=10:d=1',
    '-f','lavfi','-i','nullsrc=s=640x360:r=10:d=1,geq=lum=128+55*sin(X/40)+35*sin(Y/29):cb=128:cr=128',
    '-f','lavfi','-i','testsrc2=s=640x360:r=10:d=4',
    '-f','lavfi','-i','testsrc2=s=640x360:r=10:d=1,trim=end_frame=1,tpad=stop_mode=clone:stop_duration=2.9',
    '-filter_complex','[2:v]hue=h=96*t[sharp];[0:v][1:v][sharp][3:v]concat=n=4:v=1:a=0', '-an')
Encode ($quality + $h264 + @((Join-Path $media 'quality.mp4')))
Encode (@('-f','lavfi','-i',$test,'-vf','trim=end_frame=1,tpad=stop_mode=clone:stop_duration=3') + $h264 + @((Join-Path $media 'static.mp4')))
Encode @('-stream_loop','89','-i',$cfr,'-c','copy',(Join-Path $media 'cancel.mp4'))
[IO.File]::WriteAllText((Join-Path $media 'broken.mp4'), 'This synthetic fixture is a corrupt MP4.')
$media
