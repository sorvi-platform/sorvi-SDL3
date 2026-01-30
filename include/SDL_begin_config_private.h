#pragma once
#define SDL_PLATFORM_PRIVATE_NAME "sorvi"

#if SDL_SORVI_SDL2_COMPAT_MODE
#  define SDL_CreateThreadWithStackSize SDL_CreateThreadWithStackSize_REAL
#  define SDL_VideoInit SDL_VideoInit_REAL
#  define SDL_VideoQuit SDL_VideoQuit_REAL
#  define SDL_SetRelativeMouseMode SDL_SetRelativeMouseMode_REAL
#  define SDL_GetRelativeMouseMode SDL_GetRelativeMouseMode_REAL
#  define SDL_LockSensors SDL_LockSensors_REAL
#  define SDL_UnlockSensors SDL_UnlockSensors_REAL
#  define SDL_DYNAMIC_API 1
#  include "dynapi/SDL_dynapi_overrides.h"
#  undef SDL_DYNAMIC_API
#endif
