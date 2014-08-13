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

// bsv libraries
import Vector::*;
import GetPut::*;
import Connectable :: *;
import Clocks :: *;
import FIFO::*;
import DefaultValue::*;
import MemTypes::*;
import MemServer::*;
import ClientServer::*;
import Pipe::*;
import MemTypes::*;
import MemwriteEngine::*;

// portz libraries
import Portal::*;
import Directory::*;
import CtrlMux::*;
import Portal::*;
import Leds::*;
import XADC::*;

// generated by tool
import ImageonSerdesRequestWrapper::*;
import ImageonSerdesIndicationProxy::*;
import ImageonSensorRequestWrapper::*;
import ImageonSensorIndicationProxy::*;
import HdmiInternalRequestWrapper::*;
import HdmiInternalIndicationProxy::*;
import DmaConfigWrapper::*;
import DmaIndicationProxy::*;
import ImageonCaptureRequestWrapper::*;

// defined by user
import IserdesDatadeser::*;
import Imageon::*;
import HDMI::*;
import YUV::*;
import XilinxCells::*;
import ImageonInd::*;
import XbsvXilinxCells::*;

typedef enum { ImageonSerdesRequest, ImageonSensorRequest, HdmiInternalRequest, DmaConfig, ImageonCapture,
    ImageonSerdesIndication, ImageonSensorIndication, HdmiInternalIndication, DmaIndication} IfcNames deriving (Eq,Bits);

interface ImageCapturePins;
   interface ImageonSensorPins pins;
   interface ImageonSerdesPins serpins;
   (* prefix="" *)
   interface HDMI#(Bit#(HdmiBits)) hdmi;
   method Action fmc_video_clk1(Bit#(1) v);
endinterface
interface ImageCapture;
   interface Vector#(9,StdPortal) portals;
   interface ImageCapturePins pins;
   interface XADC             xadc;
   interface MemServer#(PhysAddrWidth,64,1)   dmaif;
endinterface

module mkImageCapture#(Clock fmc_imageon_clk1)(ImageCapture);
   Clock defaultClock <- exposeCurrentClock();
   Reset defaultReset <- exposeCurrentReset();
`ifndef BSIM
   ClockGenerator7AdvParams clockParams = defaultValue;
   clockParams.bandwidth          = "OPTIMIZED";
   clockParams.compensation       = "ZHOLD";
   clockParams.clkfbout_mult_f    = 8.000;
   clockParams.clkfbout_phase     = 0.0;
   clockParams.clkin1_period      = 6.734007; // 148.5 MHz
   clockParams.clkin2_period      = 6.734007;
   clockParams.clkout0_divide_f   = 8.000;    // 148.5 MHz
   clockParams.clkout0_duty_cycle = 0.5;
   clockParams.clkout0_phase      = 0.0000;
   clockParams.clkout1_divide     = 32;       // 37.125 MHz
   clockParams.clkout1_duty_cycle = 0.5;
   clockParams.clkout1_phase      = 0.0000;
   clockParams.divclk_divide      = 1;
   clockParams.ref_jitter1        = 0.010;
   clockParams.ref_jitter2        = 0.010;

   XClockGenerator7 clockGen <- mkClockGenerator7Adv(clockParams, clocked_by fmc_imageon_clk1);
   C2B c2b_fb <- mkC2B(clockGen.clkfbout, clocked_by clockGen.clkfbout);
   rule txoutrule5;
      clockGen.clkfbin(c2b_fb.o());
   endrule
   Clock hdmi_clock <- mkClockBUFG(clocked_by clockGen.clkout0);    // 148.5   MHz
   Clock imageon_clock <- mkClockBUFG(clocked_by clockGen.clkout1); //  37.125 MHz
`else
   Clock hdmi_clock = defaultClock;
   Clock imageon_clock = defaultClock;
`endif
   Reset hdmi_reset <- mkAsyncReset(2, defaultReset, hdmi_clock);
   Reset imageon_reset <- mkAsyncReset(2, defaultReset, imageon_clock);
   SyncPulseIfc vsyncPulse <- mkSyncHandshake(hdmi_clock, hdmi_reset, imageon_clock);

   // instantiate user portals
   // serdes: serial line protocol for wires from sensor (nothing sensor specific)
   ImageonSerdesIndicationProxy serdesIndicationProxy <- mkImageonSerdesIndicationProxy(ImageonSerdesIndication);
`ifndef BSIM
   ISerdes serdes <- mkISerdes(defaultClock, defaultReset, serdesIndicationProxy.ifc,
			clocked_by imageon_clock, reset_by imageon_reset);
   ImageonSerdesRequestWrapper serdesRequestWrapper <- mkImageonSerdesRequestWrapper(ImageonSerdesRequest,serdes.control);
   let serdes_data = serdes.data;
`else
   Wire#(Bit#(1)) serdes_reset <- mkDWire(0);
   Reg#(Bit#(50)) serdes_data_reg <- mkReg(0);
   Vector#(5, Bit#(10)) serdes_data_reg_wire = unpack(serdes_data_reg);
   let serdes_data = (interface SerdesData;
                      method Wire#(Bit#(1)) reset();
                          return serdes_reset;
                      endmethod
                      method Vector#(5, Bit#(10)) raw_data();
                          return serdes_data_reg_wire;
                      endmethod
                      endinterface);
`endif
    // mem capture
    MemwriteEngineV#(64,1,1) we <- mkMemwriteEngine();
    Reg#(ObjectPointer)      pointer <- mkReg(0);
    Reg#(Bit#(32))           numWords <- mkReg(0);
    Reg#(Bit#(16))           pushCount <- mkReg(0);
    Reg#(Bool) dmaOnce <- mkReg(True);
    rule start_dma_rule if (dmaOnce && numWords != 0);
        dmaOnce <= False;
        we.writeServers[0].request.put(MemengineCmd{pointer:pointer, base:0, len:truncate(numWords * 4), burstLen:2*4});
        serdesIndicationProxy.ifc.iserdes_dma({'hff, numWords[23:0]}); // request started
    endrule
    Reg#(Bit#(51)) serdes_sync_data <- mkSyncReg(0, imageon_clock, imageon_reset, defaultClock);
    rule sync_data;
        //serdes_sync_data <= {serdes_data.reset, serdes_data.raw_data[4], serdes_data.raw_data[3], serdes_data.raw_data[2], serdes_data.raw_data[1], serdes_data.raw_data[0]};
        serdes_sync_data <= {serdes_data.reset, pack(serdes_data.raw_data)};
    endrule
    rule send_data if (!dmaOnce && numWords != 0);
        //let v = numWords;
        let v = serdes_sync_data;
        we.dataPipes[0].enq(extend(v));
        numWords <= numWords - 1;
        if (numWords[7:0] == 'hff)
            serdesIndicationProxy.ifc.iserdes_dma({pushCount, numWords[23:8]});
        pushCount <= pushCount + 1;
    endrule
    rule dma_response;
        let rv <- we.writeServers[0].response.get;
        serdesIndicationProxy.ifc.iserdes_dma('hffffffff); // request is all finished
    endrule
   ImageonCaptureRequestWrapper imageonCaptureWrapper <- mkImageonCaptureRequestWrapper(ImageonCapture,
       (interface ImageonCaptureRequest;
            method Action startWrite(Bit#(32) wp, Bit#(32) nw);
                $display("startWrite pointer=%d numWords=%h", wp, nw);
                pointer <= wp;
                numWords  <= nw;
	    endmethod
       endinterface));
   DmaIndicationProxy dmaIndicationProxy <- mkDmaIndicationProxy(DmaIndication);
   Vector#(1, ObjectWriteClient#(64)) writeClients = cons(we.dmaClient,nil);
   MemServer#(PhysAddrWidth,64,1)   dma <- mkMemServerW(dmaIndicationProxy.ifc, writeClients);
   DmaConfigWrapper dmaRequestWrapper <- mkDmaConfigWrapper(DmaConfig, dma.request);

   // fromSensor: sensor specific processing of serdes input, resulting in pixels
   ImageonSensorIndicationProxy sensorIndicationProxy <- mkImageonSensorIndicationProxy(ImageonSensorIndication);
   ImageonSensor fromSensor <- mkImageonSensor(defaultClock, defaultReset, serdes_data, vsyncPulse.pulse(),
       hdmi_clock, hdmi_reset, sensorIndicationProxy.ifc, clocked_by imageon_clock, reset_by imageon_reset);
   ImageonSensorRequestWrapper sensorRequestWrapper <- mkImageonSensorRequestWrapper(ImageonSensorRequest,fromSensor.control);

   // hdmi: output to display
   HdmiInternalIndicationProxy hdmiIndicationProxy <- mkHdmiInternalIndicationProxy(HdmiInternalIndication);
   HdmiGenerator#(Rgb888) hdmiGen <- mkHdmiGenerator(defaultClock, defaultReset,
       vsyncPulse, hdmiIndicationProxy.ifc, clocked_by hdmi_clock, reset_by hdmi_reset);
   Rgb888ToYyuv converter <- mkRgb888ToYyuv(clocked_by hdmi_clock, reset_by hdmi_reset);
   mkConnection(hdmiGen.rgb888, converter.rgb888);
   HDMI#(Bit#(HdmiBits)) hdmisignals <- mkHDMI(converter.yyuv, clocked_by hdmi_clock, reset_by hdmi_reset);
   HdmiInternalRequestWrapper hdmiRequestWrapper <- mkHdmiInternalRequestWrapper(HdmiInternalRequest,hdmiGen.control);

   Reg#(Bool) frameStart <- mkReg(False, clocked_by imageon_clock, reset_by imageon_reset);
   Reg#(Bit#(32)) frameCount <- mkReg(0, clocked_by imageon_clock, reset_by imageon_reset);
   SyncFIFOIfc#(Tuple2#(Bit#(2),Bit#(32))) frameStartSynchronizer <- mkSyncFIFO(2, imageon_clock, imageon_reset, defaultClock);

   rule frameStartRule;
       let monitor = fromSensor.monitor();
       Bool fs = unpack(monitor[0]);
       if (fs && !frameStart) begin
	  // start of frame?
	  // need to cross the clock domain
	  frameStartSynchronizer.enq(tuple2(monitor, frameCount));
	  frameCount <= frameCount + 1;
       end
      frameStart <= fs;
   endrule
   rule frameStartIndication;
      let tpl = frameStartSynchronizer.first();
      frameStartSynchronizer.deq();
      let monitor = tpl_1(tpl);
      let count = tpl_2(tpl);
      //captureIndicationProxy.ifc.frameStart(monitor, count);
   endrule

Reg#(Bit#(10)) xsvi <- mkReg(0, clocked_by hdmi_clock, reset_by hdmi_reset);
   rule xsviConnection;
       // copy data from sensor to hdmi output
       let xsvit <- fromSensor.get_data();
       xsvi <= xsvit;
   endrule
   rule xsviput;
       Bit#(32) pixel = {8'b0, xsvi[9:2], xsvi[9:2], xsvi[9:2]};
       hdmiGen.request.put(pixel);
   endrule
   Reg#(Bit#(1)) bozobit <- mkReg(0, clocked_by hdmi_clock, reset_by hdmi_reset);
    rule bozobit_rule;
        bozobit <= ~bozobit;
    endrule
   
   Vector#(9,StdPortal) portal_array;
`ifndef BSIM
   portal_array[0] = serdesRequestWrapper.portalIfc; 
`endif
   portal_array[1] = serdesIndicationProxy.portalIfc;
   portal_array[2] = sensorRequestWrapper.portalIfc; 
   portal_array[3] = sensorIndicationProxy.portalIfc; 
   portal_array[4] = hdmiRequestWrapper.portalIfc; 
   portal_array[5] = hdmiIndicationProxy.portalIfc; 
   portal_array[6] = dmaRequestWrapper.portalIfc;
   portal_array[7] = dmaIndicationProxy.portalIfc;
   portal_array[8] = imageonCaptureWrapper.portalIfc;
   interface Vector portals = portal_array;

   interface ImageCapturePins pins;
       interface ImageonSensorPins pins = fromSensor.pins;
`ifndef BSIM
       interface ImageonSerdesPins serpins = serdes.pins;
`endif
       interface HDMI hdmi = hdmisignals;
   endinterface
   interface XADC             xadc;
        method Bit#(4) gpio;
            return { bozobit, hdmisignals.hdmi_vsync,
                //hdmisignals.hdmi_data[8], hdmisignals.hdmi_data[0]};
                hdmisignals.hdmi_hsync, hdmisignals.hdmi_de};
        endmethod
   endinterface
   interface dmaif = dma;
endmodule

module mkPortalTop(PortalTop#(PhysAddrWidth,64,ImageCapturePins,1));
   Clock defaultClock <- exposeCurrentClock();
   //Reset defaultReset <- exposeCurrentReset();
`ifndef BSIM
   B2C1 iclock <- mkB2C1();
   Clock iclock_buf <- mkClockBUFG(clocked_by iclock.c);
`else
   Clock iclock_buf = defaultClock;
`endif
   ImageCapture ic <- mkImageCapture(iclock_buf);
   
   // instantiate system directory
   StdDirectory dir <- mkStdDirectory(ic.portals);
   let ctrl_mux <- mkSlaveMux(dir,ic.portals);
   
   interface interrupt = getInterruptVector(ic.portals);
   interface slave = ctrl_mux;
   interface masters = ic.dmaif.masters;
   //interface leds = captureRequestInternal.leds;
   //interface xadc = ic.xadc;
   interface ImageCapturePins pins;
`ifndef BSIM
       method Action fmc_video_clk1(Bit#(1) v);
           iclock.inputclock(v);
       endmethod
`endif
       interface ImageonSensorPins pins = ic.pins.pins;
       interface ImageonSerdesPins serpins = ic.pins.serpins;
       interface HDMI hdmi = ic.pins.hdmi;
   endinterface
endmodule : mkPortalTop
