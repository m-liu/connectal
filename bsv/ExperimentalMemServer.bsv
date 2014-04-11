// Copyright (c) 2013 Quanta Research Cambridge, Inc.

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

// BSV Libraries
import FIFO::*;
import Vector::*;
import GetPut::*;
import ClientServer::*;
import Assert::*;

// XBSV Libraries
import Dma::*;
import PortalMemory::*;
import SGList::*;
import MemServerInternal::*;

`ifdef BSIM
import "BDPI" function ActionValue#(Bit#(32)) pareff(Bit#(32) handle, Bit#(32) size);
`endif
		 


interface MemServer#(numeric type addrWidth, numeric type dataWidth);
   interface DmaConfig request;
   interface MemMaster#(addrWidth, dataWidth) master;
endinterface
		 
	 
module mkMemServer#(DmaIndication dmaIndication,
		    Vector#(numReadClients, ObjectReadClient#(dataWidth)) readClients,
		    Vector#(numWriteClients, ObjectWriteClient#(dataWidth)) writeClients)
   (MemServer#(addrWidth, dataWidth))
   provisos(Add#(1,a__,dataWidth),
	    Add#(b__, TSub#(addrWidth, 12), 32),
	    Add#(c__, 12, addrWidth),
	    Add#(d__, addrWidth, 64),
	    Add#(e__, TSub#(addrWidth, 12), ObjectOffsetSize),
	    Add#(f__, c__, ObjectOffsetSize),
	    Add#(g__, addrWidth, 40),
	    Mul#(TDiv#(dataWidth, 8), 8, dataWidth),
	    Add#(1, numReadClients, augNumReadClients),
	    Add#(1, numWriteClients, augNumWriteClients),
	    Add#(h__, TLog#(augNumReadClients), 6),
	    Add#(i__, TLog#(augNumWriteClients), 6));
   
   TagGen#(augNumWriteClients,augNumWriteClients) writeTagGen <- mkTagGenIO;
   TagGen#(augNumReadClients,augNumReadClients) readTagGen <- mkTagGenIO;
   let rv <- mkMemServerRW(dmaIndication, readTagGen, writeTagGen, 
			   append(readClients,cons(null_object_read_client,nil)), 
			   append(writeClients,cons(null_object_write_client,nil)));
   return rv;
   
endmodule

   
module mkMemServerOO#(DmaIndication dmaIndication,
		      Vector#(numReadClients, ObjectReadClient#(dataWidth)) readClients,
		      Vector#(numWriteClients, ObjectWriteClient#(dataWidth)) writeClients)
   (MemServer#(addrWidth, dataWidth))
   provisos(Add#(1,a__,dataWidth),
	    Add#(b__, TSub#(addrWidth, 12), 32),
	    Add#(c__, 12, addrWidth),
	    Add#(d__, addrWidth, 64),
	    Add#(e__, TSub#(addrWidth, 12), ObjectOffsetSize),
	    Add#(f__, c__, ObjectOffsetSize),
	    Add#(g__, addrWidth, 40),
	    Mul#(TDiv#(dataWidth, 8), 8, dataWidth),
	    Add#(1, numReadClients, augNumReadClients),
	    Add#(1, numWriteClients, augNumWriteClients));

   TagGen#(augNumWriteClients,8) writeTagGen <- mkTagGenOO;
   TagGen#(augNumReadClients,8) readTagGen <- mkTagGenOO;
   let rv <- mkMemServerRW(dmaIndication, readTagGen, writeTagGen, 
			   append(readClients,cons(null_object_read_client,nil)), 
			   append(writeClients,cons(null_object_write_client,nil)));
   return rv;

endmodule
   
module mkMemServerRW#(DmaIndication dmaIndication,
		      TagGen#(numReadClients, numReadTags) readTagGen,
		      TagGen#(numWriteClients,numWriteTags) writeTagGen,
		      Vector#(numReadClients, ObjectReadClient#(dataWidth)) readClients,
		      Vector#(numWriteClients, ObjectWriteClient#(dataWidth)) writeClients)
   (MemServer#(addrWidth, dataWidth))
   
   provisos (Add#(1,a__,dataWidth),
	     Add#(b__, TSub#(addrWidth, 12), 32),
	     Add#(c__, 12, addrWidth),
	     Add#(d__, addrWidth, 64),
	     Add#(e__, TSub#(addrWidth, 12), ObjectOffsetSize),
	     Add#(f__, c__, ObjectOffsetSize),
	     Add#(g__, addrWidth, 40),
	     Mul#(TDiv#(dataWidth, 8), 8, dataWidth),
	     Add#(h__, TLog#(numReadTags), 6),
	     Add#(j__, TLog#(numWriteTags), 6));


   SGListMMU#(addrWidth) sgl <- mkSGListMMU(dmaIndication);
   FIFO#(void)   addrReqFifo <- mkFIFO;
   
   MemReadInternal#(addrWidth,dataWidth) reader <- mkMemReadInternal(readClients, dmaIndication, sgl.addr[0], readTagGen);
   MemWriteInternal#(addrWidth,dataWidth) writer <- mkMemWriteInternal(writeClients, dmaIndication, sgl.addr[1], writeTagGen);
   
   rule sglistEntry;
      addrReqFifo.deq;
      let physAddr <- sgl.addr[0].response.get;
      dmaIndication.addrResponse(zeroExtend(physAddr));
   endrule
   
   interface DmaConfig request;
      method Action getStateDbg(ChannelType rc);
	 let rv = ?;
	 if (rc == Read)
	    rv <- reader.dbg.dbg;
	 else
	    rv <- writer.dbg.dbg;
	 dmaIndication.reportStateDbg(rv);
      endmethod
      method Action getMemoryTraffic(ChannelType rc, Bit#(32) client);
	 if (rc == Read) begin
	    let rv <- reader.dbg.getMemoryTraffic(client);
	    dmaIndication.reportMemoryTraffic(rv);
	 end
	 else begin
	    let rv <- writer.dbg.getMemoryTraffic(client);
	    dmaIndication.reportMemoryTraffic(rv);
	 end
      endmethod
      method Action sglist(Bit#(32) pref, Bit#(ObjectOffsetSize) addr, Bit#(32) len);
	 if (bad_pointer(pref))
	    dmaIndication.badPointer(pref);
`ifdef BSIM
	 let va <- pareff(pref, len);
         addr[39:32] = truncate(pref);
`endif
	 sgl.sglist(pref, addr, len);
      endmethod
      method Action region(Bit#(32) pointer, Bit#(40) barr8, Bit#(8) off8, Bit#(40) barr4, Bit#(8) off4, Bit#(40) barr0, Bit#(8) off0);
	 sgl.region(pointer,barr8,off8,barr4,off4,barr0,off0);
      endmethod
      method Action addrRequest(Bit#(32) pointer, Bit#(32) offset);
	 addrReqFifo.enq(?);
	 sgl.addr[0].request.put(tuple2(truncate(pointer), extend(offset)));
      endmethod
   endinterface

   interface MemMaster master;
      interface MemReadClient read_client = reader.read_client;
      interface MemWriteClient write_client = writer.write_client;
   endinterface
endmodule
		 
		 
	 
	
		 
		 
		 
		 

		 
		 
		 
		 
		 