### DCT2D
#### 12bit datapath
Unoptimized:
```
+-------------------------+------+-------+------------+-----------+-------+
|        Site Type        | Used | Fixed | Prohibited | Available | Util% |
+-------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*               | 4299 |     0 |          0 |    162720 |  2.64 |
|   LUT as Logic          | 4299 |     0 |          0 |    162720 |  2.64 |
|   LUT as Memory         |    0 |     0 |          0 |     99840 |  0.00 |
| CLB Registers           | 4548 |     0 |          0 |    325440 |  1.40 |
|   Register as Flip Flop | 4548 |     0 |          0 |    325440 |  1.40 |
|   Register as Latch     |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                  |  116 |     0 |          0 |     27120 |  0.43 |
| F7 Muxes                |  108 |     0 |          0 |    108480 |  0.10 |
| F8 Muxes                |   48 |     0 |          0 |     54240 |  0.09 |
| F9 Muxes                |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets     |   96 |       |          0 |     54240 |  0.18 |
+-------------------------+------+-------+------------+-----------+-------+
+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| FDRE     | 3492 |            Register |
| LUT4     | 1688 |                 CLB |
| LUT6     | 1402 |                 CLB |
| FDSE     | 1056 |            Register |
| LUT2     |  698 |                 CLB |
| LUT5     |  409 |                 CLB |
| LUT3     |  286 |                 CLB |
| CARRY8   |  116 |                 CLB |
| MUXF7    |  108 |                 CLB |
| MUXF8    |   48 |                 CLB |
| LUT1     |   31 |                 CLB |
| DSP48E2  |   20 |          Arithmetic |
+----------+------+---------------------+
```
Optimized:
```
+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  | 2752 |     0 |          0 |    162720 |  1.69 |
|   LUT as Logic             | 2688 |     0 |          0 |    162720 |  1.65 |
|   LUT as Memory            |   64 |     0 |          0 |     99840 |  0.06 |
|     LUT as Distributed RAM |   64 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              | 1566 |     0 |          0 |    325440 |  0.48 |
|   Register as Flip Flop    | 1566 |     0 |          0 |    325440 |  0.48 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |  116 |     0 |          0 |     27120 |  0.43 |
| F7 Muxes                   |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                   |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                   |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets        |   13 |       |          0 |     54240 |  0.02 |
+----------------------------+------+-------+------------+-----------+-------+
+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| LUT6     | 1377 |                 CLB |
| FDRE     |  798 |            Register |
| FDSE     |  768 |            Register |
| LUT2     |  683 |                 CLB |
| LUT4     |  469 |                 CLB |
| LUT3     |  336 |                 CLB |
| CARRY8   |  116 |                 CLB |
| RAMD32   |  112 |                 CLB |
| LUT1     |   26 |                 CLB |
| LUT5     |   25 |                 CLB |
| DSP48E2  |   20 |          Arithmetic |
| RAMS32   |   16 |                 CLB |
+----------+------+---------------------+
```
#### 14bit datapath
(Optimized)
```
+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  | 3112 |     0 |          0 |    162720 |  1.91 |
|   LUT as Logic             | 3048 |     0 |          0 |    162720 |  1.87 |
|   LUT as Memory            |   64 |     0 |          0 |     99840 |  0.06 |
|     LUT as Distributed RAM |   64 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              | 1820 |     0 |          0 |    325440 |  0.56 |
|   Register as Flip Flop    | 1820 |     0 |          0 |    325440 |  0.56 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |  116 |     0 |          0 |     27120 |  0.43 |
| F7 Muxes                   |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                   |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                   |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets        |   13 |       |          0 |     54240 |  0.02 |
+----------------------------+------+-------+------------+-----------+-------+
+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| LUT6     | 1495 |                 CLB |
| FDRE     |  924 |            Register |
| FDSE     |  896 |            Register |
| LUT2     |  817 |                 CLB |
| LUT4     |  531 |                 CLB |
| LUT3     |  475 |                 CLB |
| CARRY8   |  116 |                 CLB |
| RAMD32   |  112 |                 CLB |
| LUT5     |   32 |                 CLB |
| DSP48E2  |   20 |          Arithmetic |
| RAMS32   |   16 |                 CLB |
| LUT1     |   11 |                 CLB |
+----------+------+---------------------+
```

### DUProc

#### 14b
```
+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| FDRE     | 3277 |            Register |
| LUT6     | 1965 |                 CLB |
| FDSE     |  938 |            Register |
| LUT2     |  843 |                 CLB |
| LUT4     |  624 |                 CLB |
| LUT3     |  619 |                 CLB |
| LUT5     |  439 |                 CLB |
| MUXF7    |  238 |                 CLB |
| CARRY8   |  116 |                 CLB |
| RAMD32   |  112 |                 CLB |
| MUXF8    |  112 |                 CLB |
| LUT1     |   24 |                 CLB |
| DSP48E2  |   22 |          Arithmetic |
| RAMS32   |   16 |                 CLB |
| FDPE     |    4 |            Register |
+----------+------+---------------------+
```
With modified zigzag module:
```
+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| LUT6     | 1612 |                 CLB |
| FDRE     | 1491 |            Register |
| FDSE     |  931 |            Register |
| LUT2     |  824 |                 CLB |
| LUT4     |  582 |                 CLB |
| LUT3     |  387 |                 CLB |
| LUT5     |  253 |                 CLB |
| CARRY8   |  116 |                 CLB |
| RAMD32   |  112 |                 CLB |
| RAMD64E  |   32 |                 CLB |
| LUT1     |   23 |                 CLB |
| DSP48E2  |   22 |          Arithmetic |
| RAMS32   |   16 |                 CLB |
| FDPE     |    4 |            Register |
+----------+------+---------------------+
```
Zigzag ping-pong buffer successfully replaced with LUTRAM. Wide register select MUXs removed as well.


### mkBlueJPEGTop_1920_12_12
#### Total
```
+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| LUT6     | 3331 |                 CLB |
| FDRE     | 2954 |            Register |
| LUT4     | 1809 |                 CLB |
| LUT2     | 1574 |                 CLB |
| FDSE     | 1259 |            Register |
| LUT3     | 1199 |                 CLB |
| LUT5     | 1030 |                 CLB |
| RAMD64E  |  624 |                 CLB |
| RAMD32   |  512 |                 CLB |
| CARRY8   |  289 |                 CLB |
| RAMS64E1 |  256 |                 CLB |
| MUXF7    |  147 |                 CLB |
| LUT1     |  107 |                 CLB |
| RAMS32   |   68 |                 CLB |
| MUXF8    |   64 |                 CLB |
| MUXF9    |   32 |                 CLB |
| RAMB36E2 |   11 |            BLOCKRAM |
| DSP48E2  |    4 |          Arithmetic |
| RAMB18E2 |    3 |            BLOCKRAM |
| FDPE     |    3 |            Register |
| FDCE     |    1 |            Register |
+----------+------+---------------------+
```
#### Hierarchy
##### Summary 
```
=== BSV Module Utilization Summary (mkBlueJPEG) ===
Module                                                Cells
------------------------------------------------------------
tables (mkTableStorage)                                 114
img_tiler (mkImageTilingEngine)                          67
ch_splt (mkChannelSplitter)                              27
y_reord (mkYBlockReorder)                                86
subs_cb (mkChromaSubsampler)                             66
subs_cr (mkChromaSubsampler)                             54
du_disp (mkDUDispatcher)                                 29
du_proc (mkDUProc)                                     7196
..du_proc_du_dbg_0 (mkDUDebug)                            0
..du_proc_du_dbg_1 (mkDUDebug)                            0
..du_proc_du_dbg_2 (mkDUDebug)                            0
..du_proc_du_dbg_3 (mkDUDebug)                            0
..du_proc_i_dct (mkDCT2D_Opt)                          6315
....du_proc_i_dct_dct_row (mkDCT1D)                    2745
....du_proc_i_dct_dct_col (mkDCT1D)                    2895
....du_proc_i_dct_tp0 (mkTransposeBufferOpt)             31
....du_proc_i_dct_tp1 (mkTransposeBufferOpt)              0
..du_proc_i_quant (mkQuantize_RT)                       185
..du_proc_i_zz (mkZigZag_Opt)                            72
rle (mkRLE)                                             118
huff (mkHuffEncoder)                                     76
stuffer (mkJPEGBitstream)                               943
fwriter (mkJPEGFramewriter)                             176
------------------------------------------------------------
TOTAL                                                  9469
```
```
============================================================
  BSV Module Utilization Report
  Top module: mkBlueJPEG
============================================================


--- tables (mkTableStorage) --- (114 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:55 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet tables_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  | 1154 |     0 |          0 |    162720 |  0.71 |
|   LUT as Logic             |  494 |     0 |          0 |    162720 |  0.30 |
|   LUT as Memory            |  660 |     0 |          0 |     99840 |  0.66 |
|     LUT as Distributed RAM |  660 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              |   57 |     0 |          0 |    325440 |  0.02 |
|   Register as Flip Flop    |   57 |     0 |          0 |    325440 |  0.02 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |    3 |     0 |          0 |     27120 |  0.01 |
| F7 Muxes                   |    3 |     0 |          0 |    108480 | <0.01 |
| F8 Muxes                   |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                   |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets        |   44 |       |          0 |     54240 |  0.08 |
+----------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 1     |          Yes |         Set |            - |
| 56    |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+-------------------+------+-------+------------+-----------+-------+
|     Site Type     | Used | Fixed | Prohibited | Available | Util% |
+-------------------+------+-------+------------+-----------+-------+
| Block RAM Tile    |    1 |     0 |          0 |       360 |  0.28 |
|   RAMB36/FIFO*    |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18          |    2 |     0 |          0 |       720 |  0.28 |
|     RAMB18E2 only |    2 |       |            |           |       |
| URAM              |    0 |     0 |          0 |        48 |  0.00 |
+-------------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| RAMD64E  |  564 |                 CLB |
| LUT6     |  348 |                 CLB |
| RAMD32   |  168 |                 CLB |
| LUT5     |   66 |                 CLB |
| LUT3     |   62 |                 CLB |
| FDRE     |   56 |            Register |
| LUT4     |   52 |                 CLB |
| LUT2     |   34 |                 CLB |
| RAMS32   |   24 |                 CLB |
| LUT1     |    4 |                 CLB |
| MUXF7    |    3 |                 CLB |
| CARRY8   |    3 |                 CLB |
| RAMB18E2 |    2 |            BLOCKRAM |
| FDSE     |    1 |            Register |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




--- img_tiler (mkImageTilingEngine) --- (67 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:55 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet img_tiler_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  |  293 |     0 |          0 |    162720 |  0.18 |
|   LUT as Logic             |  277 |     0 |          0 |    162720 |  0.17 |
|   LUT as Memory            |   16 |     0 |          0 |     99840 |  0.02 |
|     LUT as Distributed RAM |   16 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              |  178 |     0 |          0 |    325440 |  0.05 |
|   Register as Flip Flop    |  178 |     0 |          0 |    325440 |  0.05 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |    6 |     0 |          0 |     27120 |  0.02 |
| F7 Muxes                   |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                   |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                   |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets        |   14 |       |          0 |     54240 |  0.03 |
+----------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 2     |          Yes |         Set |            - |
| 176   |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+-------------------+------+-------+------------+-----------+-------+
|     Site Type     | Used | Fixed | Prohibited | Available | Util% |
+-------------------+------+-------+------------+-----------+-------+
| Block RAM Tile    |   11 |     0 |          0 |       360 |  3.06 |
|   RAMB36/FIFO*    |   11 |     0 |          0 |       360 |  3.06 |
|     RAMB36E2 only |   11 |       |            |           |       |
|   RAMB18          |    0 |     0 |          0 |       720 |  0.00 |
| URAM              |    0 |     0 |          0 |        48 |  0.00 |
+-------------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| FDRE     |  176 |            Register |
| LUT6     |   86 |                 CLB |
| LUT5     |   82 |                 CLB |
| LUT2     |   72 |                 CLB |
| LUT4     |   65 |                 CLB |
| LUT3     |   55 |                 CLB |
| RAMD32   |   28 |                 CLB |
| RAMB36E2 |   11 |            BLOCKRAM |
| LUT1     |    7 |                 CLB |
| CARRY8   |    6 |                 CLB |
| RAMS32   |    4 |                 CLB |
| FDSE     |    2 |            Register |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




--- ch_splt (mkChannelSplitter) --- (27 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:55 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet ch_splt_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+-------------------------+------+-------+------------+-----------+-------+
|        Site Type        | Used | Fixed | Prohibited | Available | Util% |
+-------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*               |    0 |     0 |          0 |    162720 |  0.00 |
|   LUT as Logic          |    0 |     0 |          0 |    162720 |  0.00 |
|   LUT as Memory         |    0 |     0 |          0 |     99840 |  0.00 |
| CLB Registers           |   27 |     0 |          0 |    325440 | <0.01 |
|   Register as Flip Flop |   27 |     0 |          0 |    325440 | <0.01 |
|   Register as Latch     |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                  |    0 |     0 |          0 |     27120 |  0.00 |
| F7 Muxes                |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets     |    1 |       |          0 |     54240 | <0.01 |
+-------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 12    |          Yes |         Set |            - |
| 15    |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| FDRE     |   15 |            Register |
| FDSE     |   12 |            Register |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




--- y_reord (mkYBlockReorder) --- (86 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:55 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet y_reord_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  |   73 |     0 |          0 |    162720 |  0.04 |
|   LUT as Logic             |   65 |     0 |          0 |    162720 |  0.04 |
|   LUT as Memory            |    8 |     0 |          0 |     99840 | <0.01 |
|     LUT as Distributed RAM |    8 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              |   81 |     0 |          0 |    325440 |  0.02 |
|   Register as Flip Flop    |   81 |     0 |          0 |    325440 |  0.02 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |    0 |     0 |          0 |     27120 |  0.00 |
| F7 Muxes                   |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                   |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                   |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets        |   12 |       |          0 |     54240 |  0.02 |
+----------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 6     |          Yes |         Set |            - |
| 75    |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+-------------------+------+-------+------------+-----------+-------+
|     Site Type     | Used | Fixed | Prohibited | Available | Util% |
+-------------------+------+-------+------------+-----------+-------+
| Block RAM Tile    |  0.5 |     0 |          0 |       360 |  0.14 |
|   RAMB36/FIFO*    |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18          |    1 |     0 |          0 |       720 |  0.14 |
|     RAMB18E2 only |    1 |       |            |           |       |
| URAM              |    0 |     0 |          0 |        48 |  0.00 |
+-------------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| FDRE     |   75 |            Register |
| LUT5     |   26 |                 CLB |
| LUT3     |   24 |                 CLB |
| LUT6     |   18 |                 CLB |
| RAMD32   |   14 |                 CLB |
| LUT4     |    9 |                 CLB |
| LUT2     |    7 |                 CLB |
| FDSE     |    6 |            Register |
| RAMS32   |    2 |                 CLB |
| RAMB18E2 |    1 |            BLOCKRAM |
| LUT1     |    1 |                 CLB |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




--- subs_cb (mkChromaSubsampler) --- (66 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:55 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet subs_cb_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  |  163 |     0 |          0 |    162720 |  0.10 |
|   LUT as Logic             |   35 |     0 |          0 |    162720 |  0.02 |
|   LUT as Memory            |  128 |     0 |          0 |     99840 |  0.13 |
|     LUT as Distributed RAM |  128 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              |   55 |     0 |          0 |    325440 |  0.02 |
|   Register as Flip Flop    |   55 |     0 |          0 |    325440 |  0.02 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |    0 |     0 |          0 |     27120 |  0.00 |
| F7 Muxes                   |   64 |     0 |          0 |    108480 |  0.06 |
| F8 Muxes                   |   32 |     0 |          0 |     54240 |  0.06 |
| F9 Muxes                   |   16 |     0 |          0 |     27120 |  0.06 |
| Unique Control Sets        |    6 |       |          0 |     54240 |  0.01 |
+----------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 8     |          Yes |         Set |            - |
| 47    |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| RAMS64E1 |  128 |                 CLB |
| MUXF7    |   64 |                 CLB |
| FDRE     |   47 |            Register |
| MUXF8    |   32 |                 CLB |
| MUXF9    |   16 |                 CLB |
| LUT5     |   16 |                 CLB |
| LUT6     |    9 |                 CLB |
| LUT3     |    9 |                 CLB |
| LUT4     |    8 |                 CLB |
| FDSE     |    8 |            Register |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




--- subs_cr (mkChromaSubsampler) --- (54 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:55 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet subs_cr_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  |  163 |     0 |          0 |    162720 |  0.10 |
|   LUT as Logic             |   35 |     0 |          0 |    162720 |  0.02 |
|   LUT as Memory            |  128 |     0 |          0 |     99840 |  0.13 |
|     LUT as Distributed RAM |  128 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              |   40 |     0 |          0 |    325440 |  0.01 |
|   Register as Flip Flop    |   40 |     0 |          0 |    325440 |  0.01 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |    0 |     0 |          0 |     27120 |  0.00 |
| F7 Muxes                   |   64 |     0 |          0 |    108480 |  0.06 |
| F8 Muxes                   |   32 |     0 |          0 |     54240 |  0.06 |
| F9 Muxes                   |   16 |     0 |          0 |     27120 |  0.06 |
| Unique Control Sets        |    5 |       |          0 |     54240 | <0.01 |
+----------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 8     |          Yes |         Set |            - |
| 32    |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| RAMS64E1 |  128 |                 CLB |
| MUXF7    |   64 |                 CLB |
| MUXF8    |   32 |                 CLB |
| FDRE     |   32 |            Register |
| MUXF9    |   16 |                 CLB |
| LUT5     |   15 |                 CLB |
| LUT3     |   12 |                 CLB |
| LUT6     |   10 |                 CLB |
| FDSE     |    8 |            Register |
| LUT4     |    7 |                 CLB |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




--- du_disp (mkDUDispatcher) --- (29 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:55 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet du_disp_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+-------------------------+------+-------+------------+-----------+-------+
|        Site Type        | Used | Fixed | Prohibited | Available | Util% |
+-------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*               |    7 |     0 |          0 |    162720 | <0.01 |
|   LUT as Logic          |    7 |     0 |          0 |    162720 | <0.01 |
|   LUT as Memory         |    0 |     0 |          0 |     99840 |  0.00 |
| CLB Registers           |   20 |     0 |          0 |    325440 | <0.01 |
|   Register as Flip Flop |   20 |     0 |          0 |    325440 | <0.01 |
|   Register as Latch     |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                  |    0 |     0 |          0 |     27120 |  0.00 |
| F7 Muxes                |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets     |    4 |       |          0 |     54240 | <0.01 |
+-------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 4     |          Yes |         Set |            - |
| 16    |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| FDRE     |   16 |            Register |
| LUT6     |    4 |                 CLB |
| FDSE     |    4 |            Register |
| LUT5     |    1 |                 CLB |
| LUT4     |    1 |                 CLB |
| LUT3     |    1 |                 CLB |
| LUT2     |    1 |                 CLB |
| LUT1     |    1 |                 CLB |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




--- du_proc (mkDUProc) --- (7196 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:56 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet du_proc_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  | 4686 |     0 |          0 |    162720 |  2.88 |
|   LUT as Logic             | 4548 |     0 |          0 |    162720 |  2.79 |
|   LUT as Memory            |  138 |     0 |          0 |     99840 |  0.14 |
|     LUT as Distributed RAM |  138 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              | 2760 |     0 |          0 |    325440 |  0.85 |
|   Register as Flip Flop    | 2760 |     0 |          0 |    325440 |  0.85 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |  202 |     0 |          0 |     27120 |  0.74 |
| F7 Muxes                   |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                   |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                   |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets        |   55 |       |          0 |     54240 |  0.10 |
+----------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 2     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 1074  |          Yes |         Set |            - |
| 1684  |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| LUT6     | 1899 |                 CLB |
| FDRE     | 1684 |            Register |
| LUT4     | 1224 |                 CLB |
| LUT2     | 1143 |                 CLB |
| FDSE     | 1074 |            Register |
| LUT3     |  677 |                 CLB |
| LUT5     |  217 |                 CLB |
| CARRY8   |  202 |                 CLB |
| RAMD32   |  146 |                 CLB |
| LUT1     |   46 |                 CLB |
| RAMD64E  |   40 |                 CLB |
| RAMS32   |   16 |                 CLB |
| FDPE     |    2 |            Register |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




---   du_proc_du_dbg_0 (mkDUDebug) --- (0 cells, possibly fully optimized)

---   du_proc_du_dbg_1 (mkDUDebug) --- (0 cells, possibly fully optimized)

---   du_proc_du_dbg_2 (mkDUDebug) --- (0 cells, possibly fully optimized)

---   du_proc_du_dbg_3 (mkDUDebug) --- (0 cells, possibly fully optimized)

---   du_proc_i_dct (mkDCT2D_Opt) --- (6315 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:56 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet du_proc_i_dct_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  | 4208 |     0 |          0 |    162720 |  2.59 |
|   LUT as Logic             | 4112 |     0 |          0 |    162720 |  2.53 |
|   LUT as Memory            |   96 |     0 |          0 |     99840 |  0.10 |
|     LUT as Distributed RAM |   96 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              | 2076 |     0 |          0 |    325440 |  0.64 |
|   Register as Flip Flop    | 2076 |     0 |          0 |    325440 |  0.64 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |  196 |     0 |          0 |     27120 |  0.72 |
| F7 Muxes                   |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                   |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                   |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets        |   14 |       |          0 |     54240 |  0.03 |
+----------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 1024  |          Yes |         Set |            - |
| 1052  |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| LUT6     | 1657 |                 CLB |
| LUT4     | 1157 |                 CLB |
| LUT2     | 1086 |                 CLB |
| FDRE     | 1052 |            Register |
| FDSE     | 1024 |            Register |
| LUT3     |  634 |                 CLB |
| CARRY8   |  196 |                 CLB |
| LUT5     |  152 |                 CLB |
| RAMD32   |  144 |                 CLB |
| LUT1     |   24 |                 CLB |
| RAMS32   |   16 |                 CLB |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




---     du_proc_i_dct_dct_row (mkDCT1D) --- (2745 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:56 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet du_proc_i_dct_dct_row_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+-------------------------+------+-------+------------+-----------+-------+
|        Site Type        | Used | Fixed | Prohibited | Available | Util% |
+-------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*               | 1584 |     0 |          0 |    162720 |  0.97 |
|   LUT as Logic          | 1584 |     0 |          0 |    162720 |  0.97 |
|   LUT as Memory         |    0 |     0 |          0 |     99840 |  0.00 |
| CLB Registers           |  903 |     0 |          0 |    325440 |  0.28 |
|   Register as Flip Flop |  903 |     0 |          0 |    325440 |  0.28 |
|   Register as Latch     |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                  |   90 |     0 |          0 |     27120 |  0.33 |
| F7 Muxes                |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets     |    5 |       |          0 |     54240 | <0.01 |
+-------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 448   |          Yes |         Set |            - |
| 455   |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| LUT6     |  626 |                 CLB |
| LUT2     |  469 |                 CLB |
| FDRE     |  455 |            Register |
| FDSE     |  448 |            Register |
| LUT4     |  422 |                 CLB |
| LUT3     |  151 |                 CLB |
| CARRY8   |   90 |                 CLB |
| LUT5     |   75 |                 CLB |
| LUT1     |    9 |                 CLB |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




---     du_proc_i_dct_dct_col (mkDCT1D) --- (2895 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:56 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet du_proc_i_dct_dct_col_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+-------------------------+------+-------+------------+-----------+-------+
|        Site Type        | Used | Fixed | Prohibited | Available | Util% |
+-------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*               | 1627 |     0 |          0 |    162720 |  1.00 |
|   LUT as Logic          | 1627 |     0 |          0 |    162720 |  1.00 |
|   LUT as Memory         |    0 |     0 |          0 |     99840 |  0.00 |
| CLB Registers           |  903 |     0 |          0 |    325440 |  0.28 |
|   Register as Flip Flop |  903 |     0 |          0 |    325440 |  0.28 |
|   Register as Latch     |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                  |   98 |     0 |          0 |     27120 |  0.36 |
| F7 Muxes                |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets     |    4 |       |          0 |     54240 | <0.01 |
+-------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 448   |          Yes |         Set |            - |
| 455   |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| LUT4     |  669 |                 CLB |
| LUT2     |  541 |                 CLB |
| FDRE     |  455 |            Register |
| FDSE     |  448 |            Register |
| LUT6     |  386 |                 CLB |
| LUT3     |  216 |                 CLB |
| CARRY8   |   98 |                 CLB |
| LUT5     |   73 |                 CLB |
| LUT1     |    9 |                 CLB |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




---     du_proc_i_dct_tp0 (mkTransposeBufferOpt) --- (31 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:56 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet du_proc_i_dct_tp0_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  |  739 |     0 |          0 |    162720 |  0.45 |
|   LUT as Logic             |  643 |     0 |          0 |    162720 |  0.40 |
|   LUT as Memory            |   96 |     0 |          0 |     99840 |  0.10 |
|     LUT as Distributed RAM |   96 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              |   12 |     0 |          0 |    325440 | <0.01 |
|   Register as Flip Flop    |   12 |     0 |          0 |    325440 | <0.01 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |    8 |     0 |          0 |     27120 |  0.03 |
| F7 Muxes                   |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                   |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                   |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets        |    6 |       |          0 |     54240 |  0.01 |
+----------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 0     |          Yes |         Set |            - |
| 12    |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| LUT6     |  517 |                 CLB |
| RAMD32   |  144 |                 CLB |
| LUT2     |   75 |                 CLB |
| LUT4     |   66 |                 CLB |
| RAMS32   |   16 |                 CLB |
| FDRE     |   12 |            Register |
| LUT3     |   10 |                 CLB |
| CARRY8   |    8 |                 CLB |
| LUT1     |    6 |                 CLB |
| LUT5     |    4 |                 CLB |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




---     du_proc_i_dct_tp1 (mkTransposeBufferOpt) --- (0 cells, possibly fully optimized)

---   du_proc_i_quant (mkQuantize_RT) --- (185 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:56 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet du_proc_i_quant_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  |  336 |     0 |          0 |    162720 |  0.21 |
|   LUT as Logic             |  334 |     0 |          0 |    162720 |  0.21 |
|   LUT as Memory            |    2 |     0 |          0 |     99840 | <0.01 |
|     LUT as Distributed RAM |    2 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              |   48 |     0 |          0 |    325440 |  0.01 |
|   Register as Flip Flop    |   48 |     0 |          0 |    325440 |  0.01 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |    6 |     0 |          0 |     27120 |  0.02 |
| F7 Muxes                   |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                   |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                   |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets        |    8 |       |          0 |     54240 |  0.01 |
+----------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 18    |          Yes |         Set |            - |
| 30    |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| LUT6     |  204 |                 CLB |
| LUT5     |   55 |                 CLB |
| LUT2     |   46 |                 CLB |
| LUT4     |   38 |                 CLB |
| FDRE     |   30 |            Register |
| LUT3     |   20 |                 CLB |
| FDSE     |   18 |            Register |
| LUT1     |   12 |                 CLB |
| CARRY8   |    6 |                 CLB |
| RAMD32   |    2 |                 CLB |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




---   du_proc_i_zz (mkZigZag_Opt) --- (72 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:56 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet du_proc_i_zz_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  |  107 |     0 |          0 |    162720 |  0.07 |
|   LUT as Logic             |   67 |     0 |          0 |    162720 |  0.04 |
|   LUT as Memory            |   40 |     0 |          0 |     99840 |  0.04 |
|     LUT as Distributed RAM |   40 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              |   52 |     0 |          0 |    325440 |  0.02 |
|   Register as Flip Flop    |   52 |     0 |          0 |    325440 |  0.02 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |    0 |     0 |          0 |     27120 |  0.00 |
| F7 Muxes                   |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                   |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                   |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets        |    9 |       |          0 |     54240 |  0.02 |
+----------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 16    |          Yes |         Set |            - |
| 36    |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| RAMD64E  |   40 |                 CLB |
| FDRE     |   36 |            Register |
| LUT6     |   26 |                 CLB |
| LUT4     |   21 |                 CLB |
| LUT3     |   18 |                 CLB |
| FDSE     |   16 |            Register |
| LUT2     |    7 |                 CLB |
| LUT1     |    6 |                 CLB |
| LUT5     |    3 |                 CLB |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




--- rle (mkRLE) --- (118 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:56 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet rle_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  |  100 |     0 |          0 |    162720 |  0.06 |
|   LUT as Logic             |   96 |     0 |          0 |    162720 |  0.06 |
|   LUT as Memory            |    4 |     0 |          0 |     99840 | <0.01 |
|     LUT as Distributed RAM |    4 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              |  126 |     0 |          0 |    325440 |  0.04 |
|   Register as Flip Flop    |  126 |     0 |          0 |    325440 |  0.04 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |    2 |     0 |          0 |     27120 | <0.01 |
| F7 Muxes                   |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                   |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                   |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets        |   12 |       |          0 |     54240 |  0.02 |
+----------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 29    |          Yes |         Set |            - |
| 97    |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| FDRE     |   97 |            Register |
| LUT6     |   48 |                 CLB |
| LUT5     |   30 |                 CLB |
| FDSE     |   29 |            Register |
| LUT4     |   12 |                 CLB |
| LUT2     |   11 |                 CLB |
| LUT3     |    9 |                 CLB |
| RAMD32   |    4 |                 CLB |
| CARRY8   |    2 |                 CLB |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




--- huff (mkHuffEncoder) --- (76 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:56 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet huff_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*                  |  292 |     0 |          0 |    162720 |  0.18 |
|   LUT as Logic             |  288 |     0 |          0 |    162720 |  0.18 |
|   LUT as Memory            |    4 |     0 |          0 |     99840 | <0.01 |
|     LUT as Distributed RAM |    4 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| CLB Registers              |   77 |     0 |          0 |    325440 |  0.02 |
|   Register as Flip Flop    |   77 |     0 |          0 |    325440 |  0.02 |
|   Register as Latch        |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                     |    6 |     0 |          0 |     27120 |  0.02 |
| F7 Muxes                   |   16 |     0 |          0 |    108480 |  0.01 |
| F8 Muxes                   |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                   |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets        |    7 |       |          0 |     54240 |  0.01 |
+----------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 32    |          Yes |         Set |            - |
| 45    |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| LUT6     |  156 |                 CLB |
| LUT5     |   70 |                 CLB |
| FDRE     |   45 |            Register |
| FDSE     |   32 |            Register |
| LUT1     |   31 |                 CLB |
| LUT3     |   27 |                 CLB |
| LUT4     |   23 |                 CLB |
| LUT2     |   20 |                 CLB |
| MUXF7    |   16 |                 CLB |
| CARRY8   |    6 |                 CLB |
| RAMD32   |    4 |                 CLB |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




--- stuffer (mkJPEGBitstream) --- (943 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:56 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet stuffer_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+-------------------------+------+-------+------------+-----------+-------+
|        Site Type        | Used | Fixed | Prohibited | Available | Util% |
+-------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*               |  771 |     0 |          0 |    162720 |  0.47 |
|   LUT as Logic          |  771 |     0 |          0 |    162720 |  0.47 |
|   LUT as Memory         |    0 |     0 |          0 |     99840 |  0.00 |
| CLB Registers           |  127 |     0 |          0 |    325440 |  0.04 |
|   Register as Flip Flop |  127 |     0 |          0 |    325440 |  0.04 |
|   Register as Latch     |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                  |   12 |     0 |          0 |     27120 |  0.04 |
| F7 Muxes                |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets     |    6 |       |          0 |     54240 |  0.01 |
+-------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 23    |          Yes |         Set |            - |
| 104   |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| LUT5     |  351 |                 CLB |
| LUT6     |  303 |                 CLB |
| LUT4     |  122 |                 CLB |
| FDRE     |  104 |            Register |
| LUT3     |   23 |                 CLB |
| FDSE     |   23 |            Register |
| CARRY8   |   12 |                 CLB |
| LUT2     |    5 |                 CLB |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




--- fwriter (mkJPEGFramewriter) --- (176 cells)
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
| Date         : Tue Apr  7 16:40:56 2026
| Host         : io running 64-bit Debian GNU/Linux 12 (bookworm)
| Command      : report_utilization -cells [get_cells -quiet fwriter_*] -return_string
| Design       : mkBlueJPEGTop_1920_12_12
| Device       : xcku3p-ffvb676-2-e
| Speed File   : -2
| Design State : Optimized
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. CLB Logic
1.1 Summary of Registers by Type
2. BLOCKRAM
3. ARITHMETIC
4. I/O
5. CLOCK
6. ADVANCED
7. CONFIGURATION
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. CLB Logic
------------

+-------------------------+------+-------+------------+-----------+-------+
|        Site Type        | Used | Fixed | Prohibited | Available | Util% |
+-------------------------+------+-------+------------+-----------+-------+
| CLB LUTs*               |   81 |     0 |          0 |    162720 |  0.05 |
|   LUT as Logic          |   81 |     0 |          0 |    162720 |  0.05 |
|   LUT as Memory         |    0 |     0 |          0 |     99840 |  0.00 |
| CLB Registers           |   84 |     0 |          0 |    325440 |  0.03 |
|   Register as Flip Flop |   84 |     0 |          0 |    325440 |  0.03 |
|   Register as Latch     |    0 |     0 |          0 |    325440 |  0.00 |
| CARRY8                  |    0 |     0 |          0 |     27120 |  0.00 |
| F7 Muxes                |    0 |     0 |          0 |    108480 |  0.00 |
| F8 Muxes                |    0 |     0 |          0 |     54240 |  0.00 |
| F9 Muxes                |    0 |     0 |          0 |     27120 |  0.00 |
| Unique Control Sets     |    7 |       |          0 |     54240 |  0.01 |
+-------------------------+------+-------+------------+-----------+-------+
* Warning! The Final LUT count, after physical optimizations and full implementation, is typically lower. Run opt_design after synthesis, if not already completed, for a more realistic count.
Warning! LUT value is adjusted to account for LUT combining.
Warning! For any ECO changes, please run place_design if there are unplaced instances
** Note: Available Control Sets calculated as Slices * 2, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 8     |          Yes |         Set |            - |
| 76    |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. BLOCKRAM
-----------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |       360 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       720 |  0.00 |
| URAM           |    0 |     0 |          0 |        48 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E2 or one FIFO18E2. However, if a FIFO18E2 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E2


3. ARITHMETIC
-------------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |      1368 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


4. I/O
------

+------------------+------+-------+------------+-----------+-------+
|     Site Type    | Used | Fixed | Prohibited | Available | Util% |
+------------------+------+-------+------------+-----------+-------+
| Bonded IOB       |    0 |     0 |          0 |       280 |  0.00 |
|   HPIOB_M        |    0 |     0 |          0 |        96 |  0.00 |
|   HPIOB_S        |    0 |     0 |          0 |        96 |  0.00 |
|   HDIOB_M        |    0 |     0 |          0 |        36 |  0.00 |
|   HDIOB_S        |    0 |     0 |          0 |        36 |  0.00 |
|   HPIOB_SNGL     |    0 |     0 |          0 |        16 |  0.00 |
| HPIOBDIFFINBUF   |    0 |     0 |          0 |        96 |  0.00 |
| HPIOBDIFFOUTBUF  |    0 |     0 |          0 |        96 |  0.00 |
| HDIOBDIFFINBUF   |    0 |     0 |          0 |        48 |  0.00 |
| BITSLICE_CONTROL |    0 |     0 |          0 |        32 |  0.00 |
| BITSLICE_RX_TX   |    0 |     0 |          0 |      1248 |  0.00 |
| BITSLICE_TX      |    0 |     0 |          0 |        32 |  0.00 |
| RIU_OR           |    0 |     0 |          0 |        16 |  0.00 |
+------------------+------+-------+------------+-----------+-------+


5. CLOCK
--------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCE     |    0 |     0 |          0 |       112 |  0.00 |
| BUFGCE_DIV |    0 |     0 |          0 |        16 |  0.00 |
| BUFG_GT    |    0 |     0 |          0 |        96 |  0.00 |
| BUFGCTRL*  |    0 |     0 |          0 |        32 |  0.00 |
| PLL        |    0 |     0 |          0 |         8 |  0.00 |
| MMCM       |    0 |     0 |          0 |         4 |  0.00 |
+------------+------+-------+------------+-----------+-------+
* Note: Each used BUFGCTRL counts as two GLOBAL CLOCK BUFFERs. This table does not include global clocking resources, only buffer cell usage. See the Clock Utilization Report (report_clock_utilization) for detailed accounting of global clocking resource availability.


6. ADVANCED
-----------

+-----------------+------+-------+------------+-----------+-------+
|    Site Type    | Used | Fixed | Prohibited | Available | Util% |
+-----------------+------+-------+------------+-----------+-------+
| CMACE4          |    0 |     0 |          0 |         1 |  0.00 |
| GTYE4_CHANNEL   |    0 |     0 |          0 |        16 |  0.00 |
| GTYE4_COMMON    |    0 |     0 |          0 |         4 |  0.00 |
| OBUFDS_GTE4     |    0 |     0 |          0 |         8 |  0.00 |
| OBUFDS_GTE4_ADV |    0 |     0 |          0 |         8 |  0.00 |
| PCIE40E4        |    0 |     0 |          0 |         1 |  0.00 |
| SYSMONE4        |    0 |     0 |          0 |         1 |  0.00 |
+-----------------+------+-------+------------+-----------+-------+


7. CONFIGURATION
----------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| DNA_PORTE2  |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE4 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE3      |    0 |     0 |          0 |         2 |  0.00 |
| MASTER_JTAG |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE3   |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| FDRE     |   76 |            Register |
| LUT6     |   34 |                 CLB |
| LUT5     |   20 |                 CLB |
| LUT4     |   19 |                 CLB |
| LUT3     |   12 |                 CLB |
| FDSE     |    8 |            Register |
| LUT2     |    7 |                 CLB |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+




============================================================
  Summary: 9469 total cells, 8952 categorized
============================================================

```