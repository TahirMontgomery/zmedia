//! Minimal FFmpeg C surface for Zig translate-c.
//! Keep this shim small — never re-export these types from zmedia's public API.
#ifndef ZMEDIA_FFMPEG_H
#define ZMEDIA_FFMPEG_H

#include <libavutil/avutil.h>
#include <libavutil/error.h>
#include <libavutil/frame.h>
#include <libavutil/imgutils.h>
#include <libavutil/channel_layout.h>
#include <libavutil/pixdesc.h>
#include <libavutil/rational.h>
#include <libavutil/samplefmt.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>

#endif
