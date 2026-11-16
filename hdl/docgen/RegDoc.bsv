package RegDoc;

import BlueCSRCore :: *;
import BlueCSRExport :: *;

import BlueJPEGRegs :: *;

//prints the encoder register map as a Markdown table during elaboration, see regmap.py
(* synthesize *)
module mkRegDoc(Empty);
    RegMapDoc_t#(32) doc <- doc_blue_csr_markdown(blue_jpeg_csrs);

    messageM("REGDOC_BEGIN\n" + doc.reg_defs + "\nREGDOC_END");
endmodule

endpackage
