
// Copyright (c) 2012 Nokia, Inc.
// Copyright (c) 2013-2014 Quanta Research Cambridge, Inc.

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
#include "sock_utils.h"

#ifdef __KERNEL__
#include "linux/delay.h"
#include "linux/file.h"
#include "linux/dma-buf.h"
#define assert(A)
#else
#include <stdlib.h>
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

#ifdef ZYNQ
#include <android/log.h>
#include <zynqportal.h>
#else
#include <pcieportal.h> // BNOC_TRACE
#endif

static void init_portal_hw(void);
int global_pa_fd = -1;
PortalInternal *utility_portal = 0x0;

#ifdef __KERNEL__
static tBoard* tboard;
#endif

void init_portal_internal(PortalInternal *pint, int id, PORTAL_INDFUNC handler, void *cb, PortalItemFunctions *item, void *param, uint32_t reqsize)
{
    int rc;
    init_portal_hw();
    memset(pint, 0, sizeof(*pint));
    if(!utility_portal)
      utility_portal = pint;
    pint->fpga_number = id;
    pint->fpga_fd = -1;
    pint->handler = handler;
    pint->cb = cb;
    pint->item = item;
    pint->muxid = -1;
    if (!item) {
#ifdef BSIM
        pint->item = &bsimfunc;
#else
        pint->item = &hardwarefunc;
#endif
    }
    pint->reqsize = reqsize;
    rc = pint->item->init(pint, param);
    if (rc != 0) {
      PORTAL_PRINTF("%s: failed to open Portal portal%d\n", __FUNCTION__, pint->fpga_number);
#ifndef __KERNEL__
      exit(1);
#endif
    }
}

int setClockFrequency(int clkNum, long requestedFrequency, long *actualFrequency)
{
    int status = 0;
    init_portal_hw();
#ifdef ZYNQ
    PortalClockRequest request;
    request.clknum = clkNum;
    request.requested_rate = requestedFrequency;
    if (utility_portal){
      status = ioctl(utility_portal->fpga_fd, PORTAL_SET_FCLK_RATE, (long)&request);
      if (status == 0 && actualFrequency)
	*actualFrequency = request.actual_rate;
      if (status < 0)
	status = errno;
    }else{ 
      status = -1;
    }
#endif
    return status;
}

static void init_portal_hw(void)
{
  unsigned int i;
  static int once = 0;

  if (once)
      return;
  once = 1;
#ifdef __KERNEL__
  tboard = get_pcie_portal_descriptor();
#endif
}

void portalTrace_start()
{
  init_portal_hw();
#if !defined(ZYNQ) && !defined(__KERNEL__)
  tTraceInfo traceInfo;
  traceInfo.trace = 1;
  assert(false);
  int res = 0; //ioctl(globalDirectory.fpga_fd,BNOC_TRACE,&traceInfo);
  if (res)
    PORTAL_PRINTF("Failed to start tracing. errno=%d\n", errno);
#endif
}
void portalTrace_stop()
{
  init_portal_hw();
#if !defined(ZYNQ) && !defined(__KERNEL__)
  tTraceInfo traceInfo;
  traceInfo.trace = 0;
  assert(false);
  int res = 0; //ioctl(globalDirectory.fpga_fd,BNOC_TRACE,&traceInfo);
  if (res)
    PORTAL_PRINTF("Failed to stop tracing. errno=%d\n", errno);
#endif
}

uint64_t portalCycleCount()
{
  unsigned int high_bits, low_bits;
  if(!utility_portal)
    return 0;
  init_portal_hw();
  volatile unsigned int *msb = &utility_portal->map_base[PORTAL_CTRL_REG_COUNTER_MSB];
  volatile unsigned int *lsb = &utility_portal->map_base[PORTAL_CTRL_REG_COUNTER_LSB];
  high_bits = utility_portal->item->read(utility_portal, &msb);
  low_bits  = utility_portal->item->read(utility_portal, &lsb);
  return (((uint64_t)high_bits)<<32) | ((uint64_t)low_bits);
}

int portalDCacheFlushInval(int fd, long size, void *__p)
{
    int i;
#if defined(__arm__)
#ifdef __KERNEL__
    struct scatterlist *sg;
    struct file *fmem = fget(fd);
    struct sg_table *sgtable = ((struct pa_buffer *)((struct dma_buf *)fmem->private_data)->priv)->sg_table;
printk("[%s:%d] flush %d\n", __FUNCTION__, __LINE__, fd);
    for_each_sg(sgtable->sgl, sg, sgtable->nents, i) {
        unsigned int length = sg->length;
        dma_addr_t start_addr = sg_phys(sg), end_addr = start_addr+length;
printk("[%s:%d] start %lx end %lx len %x\n", __FUNCTION__, __LINE__, (long)start_addr, (long)end_addr, length);
        outer_clean_range(start_addr, end_addr);
        outer_inv_range(start_addr, end_addr);
    }
    fput(fmem);
#else
  int rc;
  if (utility_portal)
    rc = ioctl(utility_portal->fpga_fd, PORTAL_DCACHE_FLUSH_INVAL, fd);
  else
    rc = -1;
  if (rc){
    PORTAL_PRINTF("portal dcache flush failed rc=%d errno=%d:%s\n", rc, errno, strerror(errno));
    return rc;
  }
#endif
#elif defined(__i386__) || defined(__x86_64__)
  // not sure any of this is necessary (mdk)
  for(i = 0; i < size; i++){
    char foo = *(((volatile char *)__p)+i);
    asm volatile("clflush %0" :: "m" (foo));
  }
  asm volatile("mfence");
#else
#error("dCAcheFlush not defined for unspecified architecture")
#endif
  //PORTAL_PRINTF("dcache flush\n");
  return 0;
}

void init_portal_memory(void)
{
#ifndef __KERNEL__
  if (global_pa_fd == -1)
      global_pa_fd = open("/dev/portalmem", O_RDWR);
  if (global_pa_fd < 0){
    PORTAL_PRINTF("Failed to open /dev/portalmem pa_fd=%d errno=%d\n", global_pa_fd, errno);
    exit(ENODEV);
  }
#endif
}

int portalAlloc(size_t size)
{
  int fd;
  init_portal_memory();
#ifdef __KERNEL__
  fd = portalmem_dmabuffer_create(size);
#else
  fd = ioctl(global_pa_fd, PA_MALLOC, size);
#endif
  PORTAL_PRINTF("alloc size=%ldMB fd=%d\n", size/(1L<<20), fd);
  return fd;
}

void *portalMmap(int fd, size_t size)
{
#ifdef __KERNEL__
  struct file *fmem = fget(fd);
  void *retptr = dma_buf_vmap(fmem->private_data);
  fput(fmem);
  return retptr;
#else      ///////////////////////// userspace version
  return mmap(0, size, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_SHARED, fd, 0);
#endif
}

void portalCheckIndication(PortalInternal *pint)
{
  volatile unsigned int *map_base = pint->map_base;
  // sanity check, to see the status of interrupt source and enable
  unsigned int queue_status;
  volatile unsigned int *statp = &map_base[PORTAL_CTRL_REG_IND_QUEUE_STATUS];
  volatile unsigned int *srcp = &map_base[PORTAL_CTRL_REG_INTERRUPT_STATUS];
  volatile unsigned int *enp = &map_base[PORTAL_CTRL_REG_INTERRUPT_ENABLE];
  while ((queue_status = pint->item->read(pint, &statp))) {
    if(0) {
      unsigned int int_src = pint->item->read(pint, &srcp);
      unsigned int int_en  = pint->item->read(pint, &enp);
      fprintf(stderr, "%s: (fpga%d) about to receive messages int=%08x en=%08x qs=%08x\n", __FUNCTION__, pint->fpga_number, int_src, int_en, queue_status);
    }
    if (!pint->handler) {
        printf("[%s:%d] missing handler!!!!\n", __FUNCTION__, __LINE__);
        exit(1);
    }
    pint->handler(pint, queue_status-1, 0);
  }
}

void send_portal_null(struct PortalInternal *pint, volatile unsigned int *buffer, unsigned int hdr, int sendFd)
{
}
int recv_portal_null(struct PortalInternal *pint, volatile unsigned int *buffer, int len, int *recvfd)
{
    return 0;
}
int busy_portal_null(struct PortalInternal *pint, volatile unsigned int *addr, const char *str)
{
    return 0;
}
void enableint_portal_null(struct PortalInternal *pint, int val)
{
}
unsigned int read_portal_memory(PortalInternal *pint, volatile unsigned int **addr)
{
    unsigned int rc = **addr;
    *addr += 1;
    return rc;
}
void write_portal_memory(PortalInternal *pint, volatile unsigned int **addr, unsigned int v)
{
    **addr = v;
    *addr += 1;
}
void write_fd_portal_memory(PortalInternal *pint, volatile unsigned int **addr, unsigned int v)
{
    **addr = v;
    *addr += 1;
}
volatile unsigned int *mapchannel_hardware(struct PortalInternal *pint, unsigned int v)
{
    return &pint->map_base[PORTAL_IND_FIFO(v)];
}
int busy_hardware(struct PortalInternal *pint, volatile unsigned int *addr, const char *str)
{
    int count = 50;
    volatile unsigned int *tempp = addr + 1;
    while (!pint->item->read(pint, &tempp) && count-- > 0)
        ; /* busy wait a bit on 'fifo not full' */
#if 1
    if (count <= 0){
        PORTAL_PRINTF("putFailed: %s\n", str);
        return 1;
    }
#else
    if (count <= 0)
    while (!pint->item->read(pint, &tempp)) {
        struct timeval timeout;
        timeout.tv_sec = 0;
        timeout.tv_usec = 10000;
        select(0, NULL, NULL, NULL, &timeout);
    }
#endif
    return 0;
}
void enableint_hardware(struct PortalInternal *pint, int val)
{
    volatile unsigned int *enp = &(pint->map_base[PORTAL_CTRL_REG_INTERRUPT_ENABLE]);
    pint->item->write(pint, &enp, val);
}
int event_hardware(struct PortalInternal *pint)
{
    // handle all messasges from this portal instance
    portalCheckIndication(pint);
    return -1;
}

static int init_hardware(struct PortalInternal *pint, void *param)
{
#if defined(__KERNEL__)
    pint->map_base = (volatile unsigned int*)(tboard->bar2io + pint->fpga_number * PORTAL_BASE_OFFSET);
#else
    int rc = 0;
    char read_status;
    char buff[128];
    snprintf(buff, sizeof(buff), "/dev/portal%d", pint->fpga_number);
#ifdef ZYNQ
    PortalEnableInterrupt intsettings = {3 << 14, (3 << 14) + 4};
    int pgfile = open("/sys/devices/amba.0/f8007000.devcfg/prog_done", O_RDONLY);
    if (pgfile == -1) {
        // 3.9 kernel uses amba.2
        pgfile = open("/sys/devices/amba.2/f8007000.devcfg/prog_done", O_RDONLY);
        if (pgfile == -1) {
            // miniitx100 uses different name!
            pgfile = open("/sys/devices/amba.0/f8007000.ps7-dev-cfg/prog_done", O_RDONLY);
        }
    }
    if (pgfile == -1) {
	PORTAL_PRINTF("failed to open /sys/devices/amba.[02]/f8007000.devcfg/prog_done %d\n", errno);
	return -1;
    }
    if (read(pgfile, &read_status, 1) != 1 || read_status != '1') {
	PORTAL_PRINTF("FPGA not programmed: %x\n", read_status);
	return -ENODEV;
    }
    close(pgfile);
    pint->fpga_fd = open(buff, O_RDWR);
    ioctl(pint->fpga_fd, PORTAL_ENABLE_INTERRUPT, &intsettings);
#else
    // FIXME: bluenoc driver only opens readonly for some reason
    pint->fpga_fd = open(buff, O_RDONLY);
#endif
    if (pint->fpga_fd < 0) {
	PORTAL_PRINTF("Failed to open %s fd=%d errno=%d\n", buff, pint->fpga_fd, errno);
	return -errno;
    }
    pint->map_base = (volatile unsigned int*)portalMmap(pint->fpga_fd, PORTAL_BASE_OFFSET);
    if (pint->map_base == MAP_FAILED) {
        PORTAL_PRINTF("Failed to mmap PortalHWRegs from fd=%d errno=%d\n", pint->fpga_fd, errno);
        return -errno;
    }  
#endif
    return 0;
}
static unsigned int read_hardware(PortalInternal *pint, volatile unsigned int **addr)
{
    return **addr;
}
static void write_hardware(PortalInternal *pint, volatile unsigned int **addr, unsigned int v)
{
    **addr = v;
}
static void write_fd_hardware(PortalInternal *pint, volatile unsigned int **addr, unsigned int v)
{
    **addr = v;
}

PortalItemFunctions hardwarefunc = {
    init_hardware, read_hardware, write_hardware, write_fd_hardware, mapchannel_hardware, mapchannel_hardware,
    send_portal_null, recv_portal_null, busy_hardware, enableint_hardware, event_hardware};
