
// defined by user
import Say::*;
// generated by tool
import SayWrapper::*;
// generated by tool
import SayProxy::*;


// this will be declared elsewhere.  we might choose better names than ctrl and m_axi ...
// users must implement this interface as their top-level HW module.
interface Top;
   interface Axi3Slave#(32,32,4,12) ctrl;
   interface ReadOnly#(Bool) interrupt;
   interface Axi3Master#(40,64,8,12) m_axi;
   interface LEDS leds;
   interface ReadOnly#(Bit#(4)) numPortals;
   // HDMI
   // serdes
   // etc.
endinterface
   

// this will be implemented by the user.  The name of the module ctor can be 
// a command line parameter but the module must implement the 'Top' interface.
module mkTop(Top);
   
   Say saySW <- mkSayProxy;
   Say sayHW <- mkSay(saySW);
   SayWrapper sayWrapper <- mkSayWrapper(sayHW);

   Vector#(2,Axi3Slave#(32,32,4,12)) ctrls_v;
   Vector#(2,ReadOnly#(Bool)) interrupts_v;

   ctrls_v[0] = sayProxy.ctrl;
   ctrls_v[1] = sayWrapper.ctrl;
   let ctrl_mux <- mkAxiSlaveMux(ctrls_v);
   
   interrupts_v[0] = sayProxy.interrupt;
   interrupts_v[1] = sayWrapper.interrupt;
   let interrupt_mux <- mkInterruptMux(interrupts_v);
   
   interface Axi3Master m_axi = ?;
   interface Axi3Slave ctrl = ctrl_mux;
   interface ReadOnly interrupt = interrupt_mux;
   interface ReadOnly numPortals;
      method Bit#(4) _read;
	 return 2;
      endmethod
   endinterface
      
endmodule


// this will be a library module defined elsewhere and instantiated in generated code
// the expectation is that the ps7 will be encapsulated into a bsv module
module mkZynqTop#(Top top) (void);
   
   PS7 ps7 <- mkPS7;
   mkConnection(top.ctrl, ps7.ctrl);
   mkConnection(top.m_axi, ps7.m_axi);
   mkConnection(top.interrupt, ps7.interrupt);
   mkConnection(top.leds, ps7.leds);
   
endmodule

// this will be a library module defined elsewhere and instantiated in generated code
// this is the 'old-style' where the wires are passed up to a top-level verilog module
module mkPcieTop#(Top top, 
		  Clock pci_sys_clk_p, 
		  Clock pci_sys_clk_n,
		  Clock sys_clk_p, 
		  Clock sys_clk_n, 
		  Reset pci_sys_reset_n) (KC705_FPGA);
   
   let contentId = 64'h4563686f;
   X7PcieBridgeIfc#(8) x7pcie <- mkX7PcieBridge(pci_sys_clk_p, pci_sys_clk_n, sys_clk_p, sys_clk_n, pci_sys_reset_n,
						top.numPortals,
						contentId );
   mkConnection(top.ctrl, x7pcie.portal0);
   mkConnection(top.m_axi, x7pcie.foo);
   mkConnection(top.interrupt, x7pcie.interrupts);

   interface pcie = x7pcie.pcie
   methods leds = top.leds;

endmodule