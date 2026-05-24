// Minimal libvlc 3.x API declarations matching the installed VLC 3.0.21 dylib.
// Only includes the functions we actually use.
#ifndef LIBVLC_COMPAT_H
#define LIBVLC_COMPAT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct libvlc_instance_t libvlc_instance_t;
typedef struct libvlc_media_t libvlc_media_t;
typedef struct libvlc_media_player_t libvlc_media_player_t;

typedef enum {
    libvlc_NothingSpecial = 0,
    libvlc_Opening,
    libvlc_Buffering,
    libvlc_Playing,
    libvlc_Paused,
    libvlc_Stopped,
    libvlc_Ended,
    libvlc_Error
} libvlc_state_t;

// Core
libvlc_instance_t *libvlc_new(int argc, const char *const *argv);
void libvlc_release(libvlc_instance_t *p_instance);

// Media
libvlc_media_t *libvlc_media_new_path(libvlc_instance_t *p_instance, const char *path);
void libvlc_media_release(libvlc_media_t *p_md);
void libvlc_media_parse(libvlc_media_t *p_md);
int64_t libvlc_media_get_duration(libvlc_media_t *p_md);

// Media Player
libvlc_media_player_t *libvlc_media_player_new_from_media(libvlc_media_t *p_md);
void libvlc_media_player_release(libvlc_media_player_t *p_mi);
void libvlc_media_player_set_nsobject(libvlc_media_player_t *p_mi, void *drawable);
int libvlc_media_player_play(libvlc_media_player_t *p_mi);
void libvlc_media_player_pause(libvlc_media_player_t *p_mi);
void libvlc_media_player_stop(libvlc_media_player_t *p_mi);
int64_t libvlc_media_player_get_time(libvlc_media_player_t *p_mi);
void libvlc_media_player_set_time(libvlc_media_player_t *p_mi, int64_t i_time);
float libvlc_media_player_get_position(libvlc_media_player_t *p_mi);
void libvlc_media_player_set_position(libvlc_media_player_t *p_mi, float f_pos);
int64_t libvlc_media_player_get_length(libvlc_media_player_t *p_mi);
float libvlc_media_player_get_rate(libvlc_media_player_t *p_mi);
int libvlc_media_player_set_rate(libvlc_media_player_t *p_mi, float rate);
libvlc_state_t libvlc_media_player_get_state(libvlc_media_player_t *p_mi);
int libvlc_video_get_size(libvlc_media_player_t *p_mi, unsigned num, unsigned *px, unsigned *py);

// Audio
int libvlc_audio_get_volume(libvlc_media_player_t *p_mi);
int libvlc_audio_set_volume(libvlc_media_player_t *p_mi, int i_volume);
int libvlc_audio_get_mute(libvlc_media_player_t *p_mi);
void libvlc_audio_set_mute(libvlc_media_player_t *p_mi, int status);

#ifdef __cplusplus
}
#endif

#endif
