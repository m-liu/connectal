
// Copyright (c) 2013 Nokia, Inc.

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

import FIFO::*;

typedef struct{
   Bit#(32) a;
   Bit#(32) b;
   } S1 deriving (Bits);

typedef struct{
   Bit#(32) a;
   Bit#(16) b;
   Bit#(7) c;
   } S2 deriving (Bits);

typedef enum {
   E1Choice1,
   E1Choice2,
   E1Choice3
   } E1 deriving (Bits,Eq);

typedef struct{
   Bit#(32) a;
   E1 e1;
   } S3 deriving (Bits);

interface StructIndication;
    method Action heard1(Bit#(32) v);
    method Action heard2(Bit#(16) a, Bit#(16) b);
    method Action heard3(S1 v);
    method Action heard4(S2 v);
    method Action heard5(Bit#(32) a, Bit#(64) b, Bit#(32) c);
    method Action heard6(Bit#(32) a, Bit#(40) b, Bit#(32) c);
    method Action heard7(Bit#(32) a, E1 e1);
endinterface

interface StructRequest;
    method Action say1(Bit#(32) v);
    method Action say2(Bit#(16) a, Bit#(16) b);
    method Action say3(S1 v);
    method Action say4(S2 v);
    method Action say5(Bit#(32)a, Bit#(64) b, Bit#(32) c);
    method Action say6(Bit#(32)a, Bit#(40) b, Bit#(32) c);
    method Action say7(S3 v);
endinterface

typedef struct {
    Bit#(32) a;
    Bit#(40) b;
    Bit#(32) c;
} Say6ReqStruct deriving (Bits);


module mkStructRequest#(StructIndication indication)(StructRequest);

   method Action say1(Bit#(32) v);
      indication.heard1(v);
      $display("(hw) say1 %d", v);
   endmethod
   
   method Action say2(Bit#(16) a, Bit#(16) b);
      indication.heard2(a,b);
      $display("(hw) say2 %d %d", a, b);
   endmethod
      
   method Action say3(S1 v);
      indication.heard3(v);
      $display("(hw) say3 S1{a:%d, b:%d}", v.a, v.b);
   endmethod
   
   method Action say4(S2 v);
      indication.heard4(v);
      $display("(hw) say4 S1{a:%d, b:%d, c:%d}", v.a, v.b, v.c);
   endmethod
      
   method Action say5(Bit#(32) a, Bit#(64) b, Bit#(32) c);
      indication.heard5(a, b, c);
      $display("(hw) say5 %h %h %h", a, b, c);
   endmethod

   method Action say6(Bit#(32) a, Bit#(40) b, Bit#(32) c);
      indication.heard6(a, b, c);
      $display("(hw) say6 %h %h %h", a, b, c);
      // Say6ReqStruct rs = Say6ReqStruct{a:32'hBBBBBBBB, b:40'hEFFECAFECA, c:32'hCCCCCCCC};
      // $display("(hw) say6 %h", pack(rs));
      // indication.heard6(rs.a, rs.b, rs.c);
   endmethod

   method Action say7(S3 v);
      indication.heard7(v.a, v.e1);
   endmethod

endmodule