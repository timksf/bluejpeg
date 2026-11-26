package DecoderTypes;

import Vector :: *;

import Types :: *;

//table ids as they appear in DHT, DQT, SOF and SOS, the decoder stores tables 0 and 1 (only 0 without chroma)
typedef Bit#(1) HuffTableId_t;
typedef Bit#(1) QuantTableId_t;
typedef Bit#(2) CompIdx_t;

//dequantized coefficients are clamped to the 8-bit baseline range, which bounds every IDCT node
typedef Int#(12) Coef_t;

typedef struct {
    UInt#(16) width;
    UInt#(16) height;
    UInt#(2)  ncomp;
} FrameInfo_t deriving(Bits, Eq, FShow);

typedef struct {
    QuantTableId_t tq;
    HuffTableId_t  td;
    HuffTableId_t  ta;
} ScanComp_t deriving(Bits, Eq, FShow);

typedef struct {
    UInt#(2)               ncomp;
    UInt#(13)              mcu_w;
    UInt#(13)              mcu_h;
    Vector#(3, ScanComp_t) comps;
} ScanCfg_t deriving(Bits, Eq, FShow);

typedef enum { Dqt, Dht, Sof, Sos, Dri } SegKind_t deriving(Bits, Eq, FShow);

//payload byte of a header segment the frame parser handles, idx counts from 0 and saturates at 31
typedef struct {
    SegKind_t kind;
    UInt#(5)  idx;
    Bool      last;
    Bit#(8)   data;
} SegByte_t deriving(Bits, Eq, FShow);

//per code length LIMIT(l) and OFFSET(l), see DecTableStorage
typedef struct {
    Vector#(16, UInt#(17)) limit;
    Vector#(16, Bit#(8))   offset;
} HuffLimits_t deriving(Bits, Eq, FShow);

typedef struct {
    Bool          ac;
    HuffTableId_t id;
    Bit#(8)       idx;
} HuffValIdx_t deriving(Bits, Eq, FShow);

//codes up to this many bits decode through the lookahead table
typedef 8 HuffLookBits;

//lookahead entry for the top HuffLookBits window bits, invalid when the code is longer
//used is the code length plus the magnitude size, the bits the symbol takes from the window
typedef struct {
    Bool     valid;
    UInt#(4) len;
    UInt#(5) used;
    Bit#(8)  sym;
} HuffLook_t deriving(Bits, Eq, FShow);

typedef struct {
    QuantTableId_t tq;
    UInt#(6)       k;
} QuantIdx_t deriving(Bits, Eq, FShow);

//unstuffed entropy-coded segment bytes, End marks the marker that closed the segment
typedef union tagged {
    Bit#(8) Byte;
    void    End;
} EcsToken_t deriving(Bits, Eq, FShow);

//position of a decoded symbol within the scan
typedef struct {
    QuantTableId_t tq;
    CompIdx_t      comp;
    UInt#(6)       k;
    Bool           last;
    Bool           mcu_end;
    Bool           last_block;
} CoefPos_t deriving(Bits, Eq, FShow);

//huffman loop output, magnitude bits are not yet sign-extended and dc is not yet predicted
typedef struct {
    CoefPos_t pos;
    Bit#(11)  raw;
    UInt#(4)  s;
    Bool      is_dc;
    Bool      first;
    Bool      has_val;
} SymToken_t deriving(Bits, Eq, FShow);

//one coefficient in zigzag order, has_val is False for a bare end of block
typedef struct {
    CoefPos_t pos;
    Coef_t    val;
    Bool      has_val;
} CoefToken_t deriving(Bits, Eq, FShow);

//dequantized and AAN-prescaled coefficient with dfrac fraction bits
typedef struct {
    CoefPos_t  pos;
    Int#(bits) val;
    Bool       has_val;
} DeqToken_t#(numeric type bits) deriving(Bits, Eq, FShow);

typedef struct {
    CompIdx_t comp;
    Bool      mcu_end;
    Bool      last;
} BlockTag_t deriving(Bits, Eq, FShow);

//one decoded sample of a single component block, samples of a block leave in row-major order
typedef struct {
    BlockTag_t tag;
    UInt#(8)   sample;
} CompSample_t deriving(Bits, Eq, FShow);

typedef struct {
    YCbCr_t pixel;
    Bool    last;
} PixelOut_t deriving(Bits, Eq, FShow);

typedef enum {
    None,
    MissingSoi,
    Unsupported,
    BadHuffCode,
    CoefOverflow
} DecError_t deriving(Bits, Eq, FShow);

endpackage
