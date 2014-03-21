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

import Vector::*;
import FIFOF::*;
import FIFO::*;
import GetPut::*;

import PortalMemory::*;
import Dma::*;

interface MemwriteEngine#(numeric type busWidth);
   method Action start(DmaPointer pointer, Bit#(DmaOffsetSize) base, Bit#(32) writeLen, Bit#(32) burstLen);
   method ActionValue#(Bool) finish();
   interface DmaWriteClient#(busWidth) dmaClient;
endinterface

module mkMemwriteEngine#(Integer cmdQDepth, FIFOF#(Bit#(busWidth)) f) (MemwriteEngine#(busWidth))

   provisos (Div#(busWidth,8,busWidthBytes));

   Reg#(Bit#(32))         numBeats <- mkReg(0);
   Reg#(Bit#(32))           reqCnt <- mkReg(0);
   Reg#(Bit#(32))          respCnt <- mkReg(0);
   
   Reg#(Bit#(DmaOffsetSize))   off <- mkReg(0);
   Reg#(Bit#(DmaOffsetSize)) delta <- mkReg(0);
   Reg#(Bit#(DmaOffsetSize))  base <- mkReg(0);

   Reg#(DmaPointer)        pointer <- mkReg(0);
   Reg#(Bit#(8))          burstLen <- mkReg(0);

   FIFOF#(Bool)                 ff <- mkSizedFIFOF(1);
   FIFOF#(Bit#(32))             wf <- mkSizedFIFOF(cmdQDepth);

   let bytes_per_beat = fromInteger(valueOf(busWidthBytes));
   
   method Action start(DmaPointer p, Bit#(DmaOffsetSize) b, Bit#(32) wl, Bit#(32) bl) if (reqCnt >= numBeats);
      numBeats <= wl/bytes_per_beat;
      reqCnt   <= 0;
      off      <= 0;
      delta    <= extend(bl);
      pointer  <= p;
      burstLen <= truncate(bl/bytes_per_beat);
      base     <= b;
      wf.enq(wl/bl); // writeLen/burstLen == numBursts.  We receive 1 writeDone for each burst transmitted
   endmethod

   method ActionValue#(Bool) finish();
      ff.deq;
      return ff.first;
   endmethod

   interface DmaWriteClient dmaClient;
      interface Get writeReq;
	 method ActionValue#(DmaRequest) get() if (reqCnt < numBeats);
	    reqCnt <= reqCnt+extend(burstLen);
	    off <= off + delta;
	    return DmaRequest {pointer: pointer, offset: off+base, burstLen: burstLen, tag: 0};
	 endmethod
      endinterface
      interface Get writeData;
	 method ActionValue#(DmaData#(busWidth)) get();
	    f.deq;
	    return DmaData{data:f.first, tag: 0};
	 endmethod
      endinterface
      interface Put writeDone;
	 method Action put(Bit#(6) tag);
	    if (respCnt+1 == wf.first) begin
	       ff.enq(True);
	       respCnt <= 0;
	       wf.deq;
	    end
	    else begin
	       respCnt <= respCnt+1;
	    end
	 endmethod
      endinterface
   endinterface

endmodule