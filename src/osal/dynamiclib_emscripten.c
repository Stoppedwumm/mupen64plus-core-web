/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *   Mupen64plus-core - osal/dynamiclib_emscripten.c                       *
 *   Mupen64Plus homepage: https://mupen64plus.org/                        *
 *   Copyright (C) 2026 Mupen64Plus developers                             *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.          *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

/* Emscripten has no practical shared library loading for mupen64plus plugins,
 * so the core and its plugins are linked into one module. A "library handle"
 * is a pointer to a NULL-terminated table of exported symbols, which the
 * frontend builds for every statically linked plugin. The core's own API is
 * exposed through osal_static_core_symbols so plugins can resolve it with the
 * same osal_dynlib_getproc() call they normally use with dlsym(). */

#include <string.h>

#define M64P_CORE_PROTOTYPES 1
#include "api/m64p_common.h"
#include "api/m64p_config.h"
#include "api/m64p_debugger.h"
#include "api/m64p_frontend.h"
#include "api/m64p_types.h"
#include "api/m64p_vidext.h"
#include "dynamiclib.h"

#define CORE_SYMBOL(name) { #name, (m64p_function) name }

const osal_static_symbol osal_static_core_symbols[] = {
    CORE_SYMBOL(PluginGetVersion),
    CORE_SYMBOL(ConfigExternalGetParameter),
    CORE_SYMBOL(ConfigExternalOpen),
    CORE_SYMBOL(ConfigExternalClose),
    CORE_SYMBOL(ConfigDeleteSection),
    CORE_SYMBOL(ConfigGetParamBool),
    CORE_SYMBOL(ConfigGetParameter),
    CORE_SYMBOL(ConfigGetParameterHelp),
    CORE_SYMBOL(ConfigGetParameterType),
    CORE_SYMBOL(ConfigGetParamFloat),
    CORE_SYMBOL(ConfigGetParamInt),
    CORE_SYMBOL(ConfigGetParamString),
    CORE_SYMBOL(ConfigGetSharedDataFilepath),
    CORE_SYMBOL(ConfigGetUserCachePath),
    CORE_SYMBOL(ConfigGetUserConfigPath),
    CORE_SYMBOL(ConfigGetUserDataPath),
    CORE_SYMBOL(ConfigHasUnsavedChanges),
    CORE_SYMBOL(ConfigListParameters),
    CORE_SYMBOL(ConfigListSections),
    CORE_SYMBOL(ConfigOpenSection),
    CORE_SYMBOL(ConfigRevertChanges),
    CORE_SYMBOL(ConfigSaveFile),
    CORE_SYMBOL(ConfigSaveSection),
    CORE_SYMBOL(ConfigSetDefaultBool),
    CORE_SYMBOL(ConfigSetDefaultFloat),
    CORE_SYMBOL(ConfigSetDefaultInt),
    CORE_SYMBOL(ConfigSetDefaultString),
    CORE_SYMBOL(ConfigSetParameter),
    CORE_SYMBOL(ConfigSetParameterHelp),
    CORE_SYMBOL(ConfigSendNetplayConfig),
    CORE_SYMBOL(ConfigReceiveNetplayConfig),
    CORE_SYMBOL(ConfigOverrideUserPaths),
    CORE_SYMBOL(CoreAddCheat),
    CORE_SYMBOL(CoreAttachPlugin),
    CORE_SYMBOL(CoreCheatEnabled),
    CORE_SYMBOL(CoreDetachPlugin),
    CORE_SYMBOL(CoreDoCommand),
    CORE_SYMBOL(CoreErrorMessage),
    CORE_SYMBOL(CoreGetAPIVersions),
    CORE_SYMBOL(CoreGetRomSettings),
    CORE_SYMBOL(CoreOverrideVidExt),
    CORE_SYMBOL(CoreShutdown),
    CORE_SYMBOL(CoreStartup),
    CORE_SYMBOL(DebugBreakpointCommand),
    CORE_SYMBOL(DebugBreakpointLookup),
    CORE_SYMBOL(DebugBreakpointTriggeredBy),
    CORE_SYMBOL(DebugDecodeOp),
    CORE_SYMBOL(DebugGetCPUDataPtr),
    CORE_SYMBOL(DebugGetState),
    CORE_SYMBOL(DebugMemGetMemInfo),
    CORE_SYMBOL(DebugMemGetPointer),
    CORE_SYMBOL(DebugMemGetRecompInfo),
    CORE_SYMBOL(DebugMemRead16),
    CORE_SYMBOL(DebugMemRead32),
    CORE_SYMBOL(DebugMemRead64),
    CORE_SYMBOL(DebugMemRead8),
    CORE_SYMBOL(DebugMemWrite16),
    CORE_SYMBOL(DebugMemWrite32),
    CORE_SYMBOL(DebugMemWrite64),
    CORE_SYMBOL(DebugMemWrite8),
    CORE_SYMBOL(DebugSetCallbacks),
    CORE_SYMBOL(DebugSetCoreCompare),
    CORE_SYMBOL(DebugSetRunState),
    CORE_SYMBOL(DebugStep),
    CORE_SYMBOL(DebugVirtualToPhysical),
    CORE_SYMBOL(VidExt_GL_GetProcAddress),
    CORE_SYMBOL(VidExt_GL_SetAttribute),
    CORE_SYMBOL(VidExt_GL_GetAttribute),
    CORE_SYMBOL(VidExt_GL_SwapBuffers),
    CORE_SYMBOL(VidExt_Init),
    CORE_SYMBOL(VidExt_InitWithRenderMode),
    CORE_SYMBOL(VidExt_ListFullscreenModes),
    CORE_SYMBOL(VidExt_ListFullscreenRates),
    CORE_SYMBOL(VidExt_Quit),
    CORE_SYMBOL(VidExt_SetCaption),
    CORE_SYMBOL(VidExt_SetVideoMode),
    CORE_SYMBOL(VidExt_SetVideoModeWithRate),
    CORE_SYMBOL(VidExt_ToggleFullScreen),
    CORE_SYMBOL(VidExt_ResizeWindow),
    CORE_SYMBOL(VidExt_GL_GetDefaultFramebuffer),
    CORE_SYMBOL(VidExt_VK_GetSurface),
    CORE_SYMBOL(VidExt_VK_GetInstanceExtensions),
    { NULL, NULL }
};

m64p_function osal_dynlib_getproc(m64p_dynlib_handle LibHandle, const char *pccProcedureName)
{
    const osal_static_symbol *sym;

    if (LibHandle == NULL || pccProcedureName == NULL)
        return NULL;

    for (sym = (const osal_static_symbol *) LibHandle; sym->name != NULL; sym++)
    {
        if (strcmp(sym->name, pccProcedureName) == 0)
            return sym->function;
    }

    return NULL;
}
