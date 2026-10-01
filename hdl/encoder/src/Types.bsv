package Types;

import Vector :: *;

import PrintUtil :: *;

typedef struct {
} NumProxy#(numeric type w) deriving(Eq, Bits);

typedef struct {
    UInt#(8) r;
    UInt#(8) g;
    UInt#(8) b;
} RGB_t deriving(FShow, Eq, Bits);

typedef struct {
    UInt#(8) y;
    UInt#(8) cb;
    UInt#(8) cr;
} YCbCr_t deriving(FShow, Eq, Bits);

typedef enum { Luma, Chroma } PixType_t deriving(FShow, Eq, Bits);

//data unit used in encoding process, in JPEG this is parameterized as 8x8
typedef struct {
    Vector#(h, Vector#(w, t)) block;
} DU_t#(type t, numeric type w, numeric type h) deriving(Eq, Bits, FShow);

//coding related types
typedef struct {
    Bit#(4) run;
    Int#(bits) val;
} ACRun_t#(numeric type bits) deriving(Eq, Bits, FShow);

typedef union tagged {
    Int#(bits)  DCDiff;
    void        EOB;
    void        ZRL;
    ACRun_t#(bits) AC;
} RLETag_t#(numeric type bits) deriving(Eq, Bits, FShow);

typedef struct {
    Bit#(32)    huffcode;
    Bit#(5)     huffsize;
    Bool        last;
} HuffCode_t deriving(Eq, Bits, FShow);

typedef struct {
    Bit#(16) code;
    Bit#(5)  size;
} HuffTableEntry_t deriving(Eq, Bits, FShow);

//huffman table write command (for runtime table configuration)
typedef enum {
    DC_Luma = 0,
    DC_Chroma = 1,
    AC_Luma = 2,
    AC_Chroma = 3
} HuffTableType_t deriving(Eq, Bits, FShow);

typedef struct {
    HuffTableType_t  table_id;
    Bit#(8)          addr;
    HuffTableEntry_t entry;
} HuffTableWrite_t deriving(Eq, Bits, FShow);

typedef struct {
    PixType_t   pt;
    Bit#(6)     idx;
} QuantTableIdx_t deriving(Eq, Bits, FShow);

typedef struct {
    HuffTableType_t htt;
    Bit#(4)         idx;
} HuffBitsIdx_t deriving(Eq, Bits, FShow);

typedef struct {
    HuffTableType_t htt;
    Bit#(8)         idx;
} HuffValIdx_t deriving(Eq, Bits, FShow);

typedef struct {
    PixType_t   pt;
    Bit#(4)     idx;
} HuffCodeDCIdx_t deriving(Eq, Bits, FShow);

typedef struct {
    PixType_t   pt;
    Bit#(8)     idx;
} HuffCodeACIdx_t deriving(Eq, Bits, FShow);

endpackage