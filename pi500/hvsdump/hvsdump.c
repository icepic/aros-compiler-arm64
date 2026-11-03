/*
    hvsdump - print the BCM2712 HVS6 display lists and what the planes scan.

    Diagnostic only. Reads the two HVS register ranges that read back without
    an abort (+0x0000-0x07ff, +0x4000-0x8dff) and pixel memory only where exec
    knows it or where it lies inside the firmware framebuffer.
*/

#include <exec/types.h>
#include <exec/memory.h>
#include <aros/kernel.h>
#include <proto/exec.h>
#include <proto/kernel.h>

#include <stdio.h>
#include <string.h>

#define HVS6_OFFSET     0x580000
#define HVS6_ID         0x00fc
#define HVS6_ID_MAGIC   0x64647276
#define DLIST_WORD      0x1000
#define DLIST_LIMIT     0x1300          /* words from the list base we may read */
#define CHAN(ch)        (0x100 + 0x40 * (ch))

static IPTR hvsbase;
static ULONG fb_addr, fb_size;

/* Experiments that change what the HVS shows; off unless named on the line */
static int opt_fixed;       /* FIXED: CTL0 alpha mask = 3 on screen-sized planes */
static int opt_alphaff;     /* ALPHAFF: alpha byte = ff in those planes' pixels  */

static ULONG rd(ULONG off)
{
    return *(volatile ULONG *)(hvsbase + off);
}

static void wr(ULONG off, ULONG value)
{
    *(volatile ULONG *)(hvsbase + off) = value;
}

static ULONG dl(ULONG w)
{
    return (w < DLIST_LIMIT) ? rd((DLIST_WORD + w) * 4) : 0;
}

static BOOL readable(ULONG addr, ULONG len)
{
    if (addr >= fb_addr && (UQUAD)addr + len <= (UQUAD)fb_addr + fb_size)
        return TRUE;
    return TypeOfMem((APTR)(IPTR)addr) && TypeOfMem((APTR)(IPTR)(addr + len - 1));
}

/* RGBA in memory order: as a little-endian word R | G<<8 | B<<16 | A<<24 */
static void scan(ULONG addr, ULONG w, ULONG h, ULONG pitch)
{
    ULONG b, y, x;

    if (!w || !h || w > 8192 || h > 8192 || pitch < w * 4)
    {
        printf("    pixels: not scanned (implausible %ux%u pitch %u)\n", w, h, pitch);
        return;
    }
    if (!readable(addr, pitch * h))
    {
        printf("    pixels: not read, %#x+%u is not known memory\n", addr, pitch * h);
        return;
    }

    for (b = 0; b < 16; b++)
    {
        ULONG y0 = h * b / 16, y1 = h * (b + 1) / 16;
        ULONG rgb = 0, a0 = 0, aff = 0, total = 0;

        for (y = y0; y < y1; y++)
        {
            volatile ULONG *row = (volatile ULONG *)(IPTR)(addr + y * pitch);

            for (x = 0; x < w; x++)
            {
                ULONG v = row[x];

                total++;
                if (v & 0x00ffffff)
                    rgb++;
                if ((v >> 24) == 0)
                    a0++;
                else if ((v >> 24) == 0xff)
                    aff++;
            }
        }
        printf("    band %2u rows %4u-%4u: rgb!=0 %8u of %8u, alpha=0 %8u, alpha=ff %8u\n",
               b, y0, y1 - 1, rgb, total, a0, aff);
    }

    {
        ULONG rows[3];
        int i, k;

        rows[0] = 0; rows[1] = h / 2; rows[2] = h - 1;
        for (i = 0; i < 3; i++)
        {
            volatile ULONG *row = (volatile ULONG *)(IPTR)(addr + rows[i] * pitch);

            printf("    row %4u first px:", rows[i]);
            for (k = 0; k < 6; k++)
                printf(" %08x", row[k]);
            printf("\n");
        }
    }
}

/* OR the alpha byte into every pixel of a plane's source buffer */
static void force_alpha(ULONG addr, ULONG w, ULONG h, ULONG pitch)
{
    ULONG y, x;

    if (!w || !h || w > 8192 || h > 8192 || pitch < w * 4 || !readable(addr, pitch * h))
    {
        printf("    ALPHAFF: not writing, buffer %#x is not known memory\n", addr);
        return;
    }
    for (y = 0; y < h; y++)
    {
        volatile ULONG *row = (volatile ULONG *)(IPTR)(addr + y * pitch);

        for (x = 0; x < w; x++)
            row[x] |= 0xff000000;
    }
    __asm__ volatile("dsb sy" ::: "memory");
    printf("    ALPHAFF: alpha set to ff in %ux%u pixels at %#x\n", w, h, addr);
}

static void dumplist(ULONG w)
{
    ULONG n;

    for (n = 0; n < 40; n++)
    {
        ULONG c0 = dl(w), next = (c0 >> 24) & 0x3f, i;

        printf("  entry at list word %#06x:", w);
        for (i = 0; i < 8; i++)
            printf(" %08x", dl(w + i));
        printf("\n");

        if (c0 & (1UL << 31))
        {
            printf("    END\n");
            return;
        }
        if (c0 & (1UL << 30))
        {
            ULONG pos0 = dl(w + 1), ctl2 = dl(w + 2), pos2 = dl(w + 3);
            ULONG ptr0 = dl(w + 5), addr = dl(w + 6), pitch = dl(w + 7);
            ULONG pw = (pos2 & 0xffff) + 1, ph = (pos2 >> 16) + 1;

            printf("    VALID fmt %u order %u unity %u alphamode %u ctl2 %08x"
                   " pos %u,%u size %ux%u\n",
                   c0 & 0x1f, (c0 >> 13) & 3, (c0 >> 15) & 1, (c0 >> 18) & 3, ctl2,
                   pos0 & 0xffff, pos0 >> 16, pw, ph);
            printf("    ptr0 %08x (upm base %#x handle %u upper %#x) addr %#x pitch %u\n",
                   ptr0, (ptr0 >> 16) & 0x1fff, ((ptr0 >> 10) & 0x1f) + 1, ptr0 & 0xff,
                   addr, pitch);
            if ((ptr0 & 0xff) == 0)
                scan(addr, pw, ph, pitch);
            else
                printf("    pixels: not scanned, address above 4GB\n");

            if (pw > 64 && ph > 64)
            {
                if (opt_fixed)
                {
                    ULONG nw = c0 | (3UL << 18);

                    wr((DLIST_WORD + w) * 4, nw);
                    printf("    FIXED: ctl0 %08x -> %08x\n", c0, nw);
                }
                if (opt_alphaff && (ptr0 & 0xff) == 0)
                    force_alpha(addr, pw, ph, pitch);
            }
        }
        else
            printf("    not valid (skipped by the HVS)\n");

        if (!next)
        {
            printf("    next=0, stopping\n");
            return;
        }
        w += next;
        if (w >= DLIST_LIMIT)
        {
            printf("    next entry outside readable list RAM\n");
            return;
        }
    }
    printf("  stopped after 40 entries\n");
}

int main(int argc, char **argv)
{
    struct KernelBase *KernelBase = OpenResource("kernel.resource");
    IPTR pb;
    ULONG ch;
    int i;

    for (i = 1; i < argc; i++)
    {
        if (!strcmp(argv[i], "FIXED"))
            opt_fixed = 1;
        else if (!strcmp(argv[i], "ALPHAFF"))
            opt_alphaff = 1;
        else
        {
            printf("usage: hvsdump [FIXED] [ALPHAFF]\n");
            return 5;
        }
    }
    if (opt_fixed || opt_alphaff)
        printf("experiment:%s%s\n", opt_fixed ? " FIXED" : "", opt_alphaff ? " ALPHAFF" : "");

    if (!KernelBase)
    {
        printf("no kernel.resource\n");
        return 20;
    }

    pb      = (IPTR)KrnGetSystemAttr(KATTR_PeripheralBase);
    fb_addr = (ULONG)(IPTR)KrnGetSystemAttr(KATTR_FrameBuffer);
    fb_size = (ULONG)(IPTR)KrnGetSystemAttr(KATTR_FrameBufferPitch) *
              (ULONG)(IPTR)KrnGetSystemAttr(KATTR_FrameBufferHeight);
    printf("peripheral base %#lx, firmware fb %#x size %u\n", (unsigned long)pb, fb_addr, fb_size);

    if (pb == 0 || pb == (IPTR)-1)
    {
        printf("no peripheral base\n");
        return 20;
    }
    if (fb_addr == (ULONG)-1)
        fb_addr = fb_size = 0;

    hvsbase = pb + HVS6_OFFSET;
    if (rd(HVS6_ID) != HVS6_ID_MAGIC)
    {
        printf("HVS6 id %08x, not %08x: not driving this\n", rd(HVS6_ID), HVS6_ID_MAGIC);
        return 10;
    }
    printf("HVS6 version %02x, dlist RAM %u words, UBM size %08x\n",
           rd(0) & 0xff, rd(4), rd(0xc));

    for (ch = 0; ch < 3; ch++)
    {
        ULONG ctrl = rd(CHAN(ch)), list = rd(CHAN(ch) + 0x10);
        ULONG stat = rd(CHAN(ch) + 0x18), act = rd(CHAN(ch) + 0x1c);

        printf("ch%u: ctrl %08x (%s %ux%u) list %#x stat %08x latched %#x\n", ch, ctrl,
               (ctrl & (1UL << 31)) ? "enabled" : "disabled",
               ((ctrl >> 16) & 0xfff) + 1, (ctrl & 0xffff) + 1, list, stat, act);
        if (ctrl & (1UL << 31))
        {
            printf(" list as latched:\n");
            dumplist(act);
            if (list != act)
            {
                printf(" list as set (differs):\n");
                dumplist(list);
            }
        }
    }
    return 0;
}
