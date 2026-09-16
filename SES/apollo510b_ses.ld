/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright (c) 2026 Mariusz Łacina
 * All rights reserved.
 *
 * Project-specific GNU ld linker script for the Ambiq Apollo510B platform
 * and SEGGER Embedded Studio.
 *
 * The Apollo510B memory map was based on the device memory map documented
 * in the Apollo510B SoC datasheet, while the baseline Cortex-M section
 * organization was informed by the linker configuration used in
 * AmbiqSuite SDK 5.2.0.
 *
 * This script contains substantial project-specific implementation, including
 * selectable NVM, ITCM/DTCM and Shared SRAM layouts, SEGGER Embedded Studio
 * stack integration, generated memory symbols, and link-time memory-layout
 * validation.
 *
 * This file is project-authored and is not part of the AmbiqSuite SDK.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

/*
 * Application NVM selection:
 *   0 = NVM0 only,     0x00410000 - 0x005FFFFF (1984 KiB)
 *       Match with AM_HAL_PWRCTRL_NVM0_ONLY.
 *   1 = NVM0 + NVM1,  0x00410000 - 0x007FFFFF (4032 KiB)
 *       Match with AM_HAL_PWRCTRL_NVM0_AND_NVM1.
 *
 * 0x00400000 - 0x0040FFFF is reserved for the Secure Boot Loader, therefore
 * the application always starts at 0x00410000.
 *
 * Default: NVM0 + NVM1, matching g_DefaultMcuMemCfg in AmbiqSuite 5.2.0.
 * Override with:
 *   --defsym=NVM_SELECT=0
 *   --defsym=NVM_SELECT=1
 *
 * ERR044 warning: powering down NVM1 while NVM0 is powered on can hang the
 * MRAM controller on a POR/POI reset. A build restricted to NVM0 does not by
 * itself make that runtime power configuration safe.
 * AM_HAL_PWRCTRL_NVM_NONE is intentionally not offered because .text executes
 * directly from application NVM.
 */

/*
 * Coupled ITCM/DTCM selection:
 *   0 =  32 KiB ITCM + 128 KiB DTCM
 *       Match with AM_HAL_PWRCTRL_ITCM32K_DTCM128K.
 *   1 = 128 KiB ITCM + 256 KiB DTCM
 *       Match with AM_HAL_PWRCTRL_ITCM128K_DTCM256K.
 *   2 = 256 KiB ITCM + 512 KiB DTCM
 *       Match with AM_HAL_PWRCTRL_ITCM256K_DTCM512K.
 *
 * The upper 16 KiB of the selected DTCM range is reserved for a 4 KiB heap
 * followed by a 12 KiB stack. The remaining lower range is available to
 * .data and .bss. The HAL's 0 KiB ITCM + 0 KiB DTCM mode is intentionally not
 * offered because this application layout requires DTCM for data and stack.
 *
 * Default: 256 KiB ITCM + 512 KiB DTCM, matching g_DefaultMcuMemCfg.
 * Override with:
 *   --defsym=TCM_SELECT=0
 *   --defsym=TCM_SELECT=1
 *   --defsym=TCM_SELECT=2
 */

/*
 * Shared SRAM selection:
 *   0 = NONE, no Shared SRAM; .shared must be empty
 *   1 = 1 MiB, GROUP0
 *   2 = 2 MiB, GROUP0 + GROUP1
 *   3 = 3 MiB, GROUP0 + GROUP1 + GROUP2
 *
 * Match the selection with AM_HAL_PWRCTRL_SRAM_NONE, SRAM_1M, SRAM_2M, or
 * SRAM_3M respectively. The selected groups must also be retained whenever
 * data in .shared has to survive deep sleep.
 *
 * Default: 3 MiB, matching g_DefaultSRAMCfg in AmbiqSuite 5.2.0.
 * Override with:
 *   --defsym=SHARED_SRAM_SELECT=0
 *   --defsym=SHARED_SRAM_SELECT=1
 *   --defsym=SHARED_SRAM_SELECT=2
 *   --defsym=SHARED_SRAM_SELECT=3
 */

/*
 * Apollo510/Apollo510B DMA errata relevant to this layout:
 *
 * ERR014: a DMA transfer to or from TCM must not cross a 4 KiB boundary.
 * TCM must be powered and the CPU must not be in deep sleep during the access.
 *
 * ERR018: DMA transfers must not cross the DTCM/SSRAM boundary or the 1 MiB
 * SSRAM group boundaries at 0x20180000 and 0x20280000.
 * DMA transfers must also not cross the NVM0/NVM1 boundary at 0x00600000.
 *
 * The linker models the memory boundaries but cannot validate runtime DMA
 * transfer addresses and lengths.
 */

PROVIDE(NVM_SELECT = 1);
PROVIDE(TCM_SELECT = 2);
PROVIDE(SHARED_SRAM_SELECT = 3);

ENTRY(Reset_Handler)

MEMORY
{
    FLASH (rx) : ORIGIN = 0x00410000,
                 LENGTH = (NVM_SELECT == 0 ? 0x1F0000 : 0x3F0000)

    ITCM (rwx) : ORIGIN = 0x00000000,
                 LENGTH = (TCM_SELECT == 0 ? 0x08000 :
                           TCM_SELECT == 1 ? 0x20000 :
                                             0x40000)

    DTCM (rwx) : ORIGIN = 0x20000000,
                 LENGTH = (TCM_SELECT == 0 ? 0x1C000 :
                           TCM_SELECT == 1 ? 0x3C000 :
                                             0x7C000)

    /* Physical Shared SRAM groups documented by ERR018. */
    SHARED_SRAM_GROUP0 (rwx) : ORIGIN = 0x20080000, LENGTH = 0x100000
    SHARED_SRAM_GROUP1 (rwx) : ORIGIN = 0x20180000, LENGTH = 0x100000
    SHARED_SRAM_GROUP2 (rwx) : ORIGIN = 0x20280000, LENGTH = 0x100000

    /* The only Shared SRAM region used for output-section allocation. */
    SHARED_SRAM (rwx) : ORIGIN = 0x20080000,
                        LENGTH = (SHARED_SRAM_SELECT == 0 ? 0x000000 :
                                  SHARED_SRAM_SELECT == 1 ? 0x100000 :
                                  SHARED_SRAM_SELECT == 2 ? 0x200000 :
                                                                    0x300000)

    HEAP_RAM (rw) :
        ORIGIN = (TCM_SELECT == 0 ? 0x2001C000 :
                  TCM_SELECT == 1 ? 0x2003C000 :
                                    0x2007C000),
        LENGTH = 0x01000

    STACK_RAM (rw) :
        ORIGIN = (TCM_SELECT == 0 ? 0x2001D000 :
                  TCM_SELECT == 1 ? 0x2003D000 :
                                    0x2007D000),
        LENGTH = 0x03000
}

ASSERT(NVM_SELECT == 0 || NVM_SELECT == 1,
       "NVM_SELECT must be 0 (NVM0 only) or 1 (NVM0 + NVM1)")

ASSERT(TCM_SELECT >= 0 && TCM_SELECT <= 2,
       "TCM_SELECT must be 0 (32K/128K), 1 (128K/256K), or 2 (256K/512K)")

ASSERT(SHARED_SRAM_SELECT >= 0 && SHARED_SRAM_SELECT <= 3,
       "SHARED_SRAM_SELECT must be 0 (NONE), 1 (1M), 2 (2M), or 3 (3M)")

__nvm_selection__ = NVM_SELECT;
__flash_start__    = ORIGIN(FLASH);
__flash_end__      = ORIGIN(FLASH) + LENGTH(FLASH) - 1;

__tcm_selection__ = TCM_SELECT;
__itcm_start__    = ORIGIN(ITCM);
__itcm_end__      = ORIGIN(ITCM) + LENGTH(ITCM) - 1;
__dtcm_start__    = ORIGIN(DTCM);
__dtcm_end__      = ORIGIN(STACK_RAM) + LENGTH(STACK_RAM) - 1;

__shared_sram_selection__ = SHARED_SRAM_SELECT;
__shared_sram_start__     = ORIGIN(SHARED_SRAM);
__shared_sram_limit__     = ORIGIN(SHARED_SRAM) + LENGTH(SHARED_SRAM);

SECTIONS
{
    .text :
    {
        . = ALIGN(4);
        __text_start__ = .;

        KEEP(*(.isr_vector))
        KEEP(*(.patch))

        *(.text .text.* .gnu.linkonce.t.*)
        *(.rodata .rodata.* .gnu.linkonce.r.*)

        . = ALIGN(4);
        _etext = .;
        __text_end__ = .;
    } > FLASH

    .ARM.extab :
    {
        . = ALIGN(4);
        *(.ARM.extab .ARM.extab.* .gnu.linkonce.armextab.*)
        . = ALIGN(4);
    } > FLASH

    .ARM.exidx :
    {
        . = ALIGN(4);
        __exidx_start = .;
        *(.ARM.exidx .ARM.exidx.* .gnu.linkonce.armexidx.*)
        __exidx_end = .;
        . = ALIGN(4);
    } > FLASH

    .itcm_text :
    {
        . = ALIGN(4);
        _s_itcm_text = .;
        *(.itcm_text .itcm_text.*)
        . = ALIGN(4);
        _e_itcm_text = .;
    } > ITCM AT> FLASH
    _init_itcm_text = LOADADDR(.itcm_text);

    .data :
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data .data.* .gnu.linkonce.d.*)
        . = ALIGN(4);
        _edata = .;
    } > DTCM AT> FLASH
    _init_data = LOADADDR(.data);

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss .bss.* .gnu.linkonce.b.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > DTCM

    .heap (NOLOAD) :
    {
        . = ALIGN(8);
        __heap_start__ = .;
        end = __heap_start__;
        _end = __heap_start__;
        __end = __heap_start__;

        KEEP(*(.heap .heap.*))

        . = ORIGIN(HEAP_RAM) + LENGTH(HEAP_RAM);
        __heap_end__ = .;
        __HeapLimit = .;
    } > HEAP_RAM

    .stack (NOLOAD) :
    {
        . = ALIGN(8);
        __StackLimit = .;

        KEEP(*(.stack .stack.*))

        . = ALIGN(8);
        __StackTop = .;
    } > STACK_RAM

    .shared (NOLOAD) :
    {
        . = ALIGN(4);
        KEEP(*(.resource_table .resource_table.*))
        KEEP(*(.shared .shared.*))
        . = ALIGN(4);
    } > SHARED_SRAM

    .ARM.attributes 0 :
    {
        *(.ARM.attributes)
    }
}

ASSERT(SIZEOF(.itcm_text) <= LENGTH(ITCM),
       "Apollo510B .itcm_text exceeds the selected ITCM size")

ASSERT(__StackTop <= ORIGIN(STACK_RAM) + LENGTH(STACK_RAM),
       "Apollo510B stack exceeds STACK_RAM")

ASSERT(ORIGIN(DTCM) + LENGTH(DTCM) <= ORIGIN(HEAP_RAM) &&
       ORIGIN(HEAP_RAM) + LENGTH(HEAP_RAM) <= ORIGIN(STACK_RAM) &&
       ORIGIN(STACK_RAM) + LENGTH(STACK_RAM) == __dtcm_end__ + 1,
       "Apollo510B DTCM regions exceed the selected powered DTCM range")

ASSERT(SIZEOF(.shared) <= LENGTH(SHARED_SRAM),
       "Apollo510B .shared requires more Shared SRAM than selected")
