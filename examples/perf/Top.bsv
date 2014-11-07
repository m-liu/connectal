// bsv libraries
import SpecialFIFOs::*;
import Vector::*;
import StmtFSM::*;
import FIFO::*;

// portz libraries
import CtrlMux::*;
import Portal::*;
import Leds::*;
import ConnectalMemory::*;
import MemTypes::*;
import DmaUtils::*;
import MemServer::*;
import MMU::*;

// generated by tool
import PerfRequest::*;
import MemServerRequest::*;
import MMURequest::*;
import PerfIndication::*;
import MemServerIndication::*;
import MMUIndication::*;

// defined by user
import Perf::*;

typedef enum {PerfIndication, PerfRequest, HostMemServerIndication, HostMemServerRequest, HostMMURequest, HostMMUIndication} IfcNames deriving (Eq,Bits);

module mkConnectalTop(StdConnectalDmaTop#(PhysAddrWidth));

   DmaReadBuffer#(64,8)   dma_stream_read_chan <- mkDmaReadBuffer();
   DmaWriteBuffer#(64,8) dma_stream_write_chan <- mkDmaWriteBuffer();
   DmaReadBuffer#(64,8)     dma_word_read_chan <- mkDmaReadBuffer();
   DmaWriteBuffer#(64,8)  dma_debug_write_chan <- mkDmaWriteBuffer();

   Vector#(2,  MemReadClient#(64))   readClients = newVector();
   readClients[0] = dma_stream_read_chan.dmaClient;
   readClients[1] = dma_word_read_chan.dmaClient;

   Vector#(2, MemWriteClient#(64)) writeClients = newVector();
   writeClients[0] = dma_stream_write_chan.dmaClient;
   writeClients[1] = dma_debug_write_chan.dmaClient;

   MMUIndicationProxy hostMMUIndicationProxy <- mkMMUIndicationProxy(HostMMUIndication);
   MMU#(PhysAddrWidth) hostMMU <- mkMMU(0, True, hostMMUIndicationProxy.ifc);
   MMURequestWrapper hostMMURequestWrapper <- mkMMURequestWrapper(HostMMURequest, hostMMU.request);

   MemServerIndicationProxy hostMemServerIndicationProxy <- mkMemServerIndicationProxy(HostMemServerIndication);
   MemServer#(PhysAddrWidth,64,1) dma <- mkMemServerRW(hostMemServerIndicationProxy.ifc, readClients, writeClients, cons(hostMMU,nil));
   MemServerRequestWrapper hostMemServerRequestWrapper <- mkMemServerRequestWrapper(HostMemServerRequest, dma.request);

   PerfIndicationProxy perfIndicationProxy <- mkPerfIndicationProxy(PerfIndication);
   PerfRequest perfRequest <- mkPerfRequest(perfIndicationProxy.ifc, dma_stream_read_chan.dmaServer,
						  dma_stream_write_chan.dmaServer, dma_word_read_chan.dmaServer);
   PerfRequestWrapper perfRequestWrapper <- mkPerfRequestWrapper(PerfRequest,perfRequest);

   Vector#(6,StdPortal) portals;
   portals[0] = perfRequestWrapper.portalIfc;
   portals[1] = perfIndicationProxy.portalIfc; 
   portals[2] = hostMemServerRequestWrapper.portalIfc;
   portals[3] = hostMemServerIndicationProxy.portalIfc; 
   portals[4] = hostMMURequestWrapper.portalIfc;
   portals[5] = hostMMUIndicationProxy.portalIfc;
   let ctrl_mux <- mkSlaveMux(portals);
   
   interface interrupt = getInterruptVector(portals);
   interface slave = ctrl_mux;
   interface masters = dma.masters;
   interface leds = default_leds;
endmodule


