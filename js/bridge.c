/*
 * The three espeak-ng calls voice-core's EspeakPhonemizer makes, for
 * WebAssembly: initialise, choose a voice, and step through a text one clause
 * at a time. The clause loop and the terminator mapping are not here; they
 * are in phonemizer.mjs, mirroring EspeakPhonemizer.swift line for line, so
 * the two can be read against each other.
 */
#include <stdlib.h>
#include <string.h>
#include <espeak-ng/speak_lib.h>

/* espeak's own cursor through the text being phonemized. Static because
 * espeak_TextToPhonemesWithTerminator advances it and expects to be handed
 * the same pointer back, as the Swift version's `cursor` is across its loop. */
static char *vc_buffer = NULL;
static const void *vc_cursor = NULL;

int vc_init(const char *data_parent) {
  /* AUDIO_OUTPUT_SYNCHRONOUS, buflength 0, options 0: the Swift call. */
  return espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, data_parent, 0);
}

int vc_set_voice(const char *name) {
  return (int)espeak_SetVoiceByName(name);
}

void vc_begin(const char *text) {
  if (vc_buffer) { free(vc_buffer); vc_buffer = NULL; }
  vc_buffer = strdup(text);
  vc_cursor = (const void *)vc_buffer;
}

/* The next clause's phonemes, or NULL when the text is spent. The terminator
 * is written unmasked; the caller masks and maps it, as the Swift does. */
const char *vc_next(int *out_terminator) {
  if (!vc_cursor) return NULL;
  int terminator = 0;
  /* espeakCHARS_AUTO = 0, espeakPHONEMES_IPA = 0x02 */
  const char *phonemes = espeak_TextToPhonemesWithTerminator(&vc_cursor, 0, 0x02, &terminator);
  if (out_terminator) *out_terminator = terminator;
  return phonemes;
}

const char *vc_version(void) {
  const char *path = NULL;
  return espeak_Info(&path);
}
