// bsv libraries
import SpecialFIFOs::*;
import Vector::*;
import StmtFSM::*;
import FIFO::*;

// portz libraries
import AxiMasterSlave::*;
import Directory::*;
import CtrlMux::*;
import Portal::*;
import Leds::*;
import PortalMemory::*;
import Dma::*;
import DmaUtils::*;
import AxiDma::*;

// generated by tool
import MemrwRequestWrapper::*;
import DmaConfigWrapper::*;
import MemrwIndicationProxy::*;
import DmaIndicationProxy::*;

// defined by user
import Memrw::*;

typedef enum {MemrwIndication, MemrwRequest, DmaIndication, DmaConfig} IfcNames deriving (Eq,Bits);

module mkPortalTop(StdPortalTop#(addrWidth)) 

   provisos(Add#(addrWidth, a__, 52),
	    Add#(b__, addrWidth, 64),
	    Add#(c__, 12, addrWidth),
	    Add#(addrWidth, d__, 44),
	    Add#(e__, c__, 40),
	    Add#(f__, addrWidth, 40));


   MemrwIndicationProxy memrwIndicationProxy <- mkMemrwIndicationProxy(MemrwIndication);
   Memrw memrw <- mkMemrw(memrwIndicationProxy.ifc);
   MemrwRequestWrapper memrwRequestWrapper <- mkMemrwRequestWrapper(MemrwRequest,memrw.request);
   
   DmaIndicationProxy dmaIndicationProxy <- mkDmaIndicationProxy(DmaIndication);
   Vector#(1,  DmaReadClient#(64))   readClients = cons(memrw.dmaReadClient, nil);
   Vector#(1, DmaWriteClient#(64)) writeClients = cons(memrw.dmaWriteClient, nil);
   AxiDmaServer#(addrWidth, 64)   dma <- mkAxiDmaServer(dmaIndicationProxy.ifc, readClients, writeClients);
   DmaConfigWrapper dmaRequestWrapper <- mkDmaConfigWrapper(DmaConfig,dma.request);
   
   Vector#(4,StdPortal) portals;
   portals[0] = memrwRequestWrapper.portalIfc;
   portals[1] = memrwIndicationProxy.portalIfc; 
   portals[2] = dmaRequestWrapper.portalIfc;
   portals[3] = dmaIndicationProxy.portalIfc; 
   
   StdDirectory dir <- mkStdDirectory(portals);
   let ctrl_mux <- mkAxiSlaveMux(dir,portals);
   
   interface interrupt = getInterruptVector(portals);
   interface ctrl = ctrl_mux;
   interface m_axi = dma.m_axi;
   interface leds = default_leds;
endmodule

