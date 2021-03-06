// Copyright (c) 2014 Quanta Research Cambridge, Inc.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#include "portal.h"
#include "dmaManager.h"
#include "sock_utils.h"

#ifdef __KERNEL__
#include "linux/delay.h"
#include "linux/file.h"
#include "linux/dma-buf.h"
#define assert(A)
#else
#include <string.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <time.h> // ctime
#endif
#include "portalmem.h" // PA_MALLOC

static int init_shared(struct PortalInternal *pint, void *aparam)
{
    PortalSharedParam *param = (PortalSharedParam *)aparam;
    if (param) {
        int fd = portalAlloc(param->size);
        pint->map_base = (volatile unsigned int *)portalMmap(fd, param->size);
        pint->map_base[SHARED_LIMIT] = param->size/sizeof(uint32_t);
        pint->map_base[SHARED_WRITE] = SHARED_START;
        pint->map_base[SHARED_READ] = SHARED_START;
        pint->map_base[SHARED_START] = 0;
        unsigned int ref = param->dma->reference(fd);
        MMURequest_setInterface(param->dma->priv.sglDevice, pint->fpga_number, ref);
    }
    return 0;
}
static volatile unsigned int *mapchannel_sharedInd(struct PortalInternal *pint, unsigned int v)
{
    return &pint->map_base[pint->map_base[SHARED_READ]+1];
}
static volatile unsigned int *mapchannel_sharedReq(struct PortalInternal *pint, unsigned int v)
{
    return &pint->map_base[pint->map_base[SHARED_WRITE]+1];
}
static int busywait_shared(struct PortalInternal *pint, volatile unsigned int *addr, const char *str)
{
    int reqwords = pint->reqsize/sizeof(uint32_t) + 1;
    reqwords = (reqwords + 1) & 0xfffe;
    volatile unsigned int *map_base = pint->map_base;
    int limit = map_base[SHARED_LIMIT];
    while (1) {
	int write = map_base[SHARED_WRITE];
	int read = map_base[SHARED_READ];
	int avail;
	if (write >= read) {
	    avail = limit - (write - read) - 4;
	} else {
	    avail = read - write;
	}
	int enqready = (avail > 2*reqwords); // might have to wrap
	//fprintf(stderr, "busywait_shared limit=%d write=%d read=%d avail=%d enqready=%d\n", limit, write, read, avail, enqready);
	if (avail < reqwords)
	    fprintf(stderr, "****\n    not enough space available \n****\n");
	if (enqready)
	    return 0;
    }
    return 0;
}
static inline unsigned int increment_shared(PortalInternal *pint, unsigned int newp)
{
    int reqwords = pint->reqsize/sizeof(uint32_t) + 1;
    reqwords = (reqwords + 1) & 0xfffe;
    if (newp + reqwords >= pint->map_base[SHARED_LIMIT])
        newp = SHARED_START;
    return newp;
}
static void send_shared(struct PortalInternal *pint, volatile unsigned int *buff, unsigned int hdr, int sendFd)
{
    int reqwords = hdr & 0xffff;
    int needs_padding = (reqwords & 1);

    pint->map_base[pint->map_base[SHARED_WRITE]] = hdr;
    if (needs_padding) {
	// pad req
	pint->map_base[pint->map_base[SHARED_WRITE] + reqwords] = 0xffff0001;
	reqwords = (reqwords + 1) & 0xfffe;
    }
    pint->map_base[SHARED_WRITE] = increment_shared(pint, pint->map_base[SHARED_WRITE] + reqwords);
    //fprintf(stderr, "send_shared head=%d padded=%d hdr=%08x\n", pint->map_base[SHARED_WRITE], needs_padding, hdr);
    pint->map_base[pint->map_base[SHARED_WRITE]] = 0;
}
static int event_shared(struct PortalInternal *pint)
{
    if (pint->map_base && pint->map_base[SHARED_READ] != pint->map_base[SHARED_WRITE]) {
        unsigned int hdr = pint->map_base[pint->map_base[SHARED_READ]];
	unsigned short msg_num = hdr >> 16;
	unsigned short msg_words = hdr & 0xffff;
	msg_words = (msg_words + 1) & 0xfffe;
	if (msg_num != 0xffff)
	    pint->handler(pint, msg_num, 0);
        pint->map_base[SHARED_READ] = increment_shared(pint, pint->map_base[SHARED_READ] + msg_words);
    }
    return -1;
}
PortalItemFunctions sharedfunc = {
    init_shared, read_portal_memory, write_portal_memory, write_fd_portal_memory, mapchannel_sharedInd, mapchannel_sharedReq,
    send_shared, recv_portal_null, busywait_shared, enableint_portal_null, event_shared};


