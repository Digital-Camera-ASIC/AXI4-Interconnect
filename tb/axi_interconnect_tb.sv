`timescale 1ns / 1ps
// Testbench configuration
`define NUM_TRANS           10
// Random test mode
`define BURST_MODE          0
`define BURST_MODE_WR       2
`define ARBITRATION_MODE    1

`define MAX_LENGTH          8

// Interconnect configuration
parameter                       MST_AMT             = 4;
parameter                       SLV_AMT             = 2;
parameter                       OUTSTANDING_AMT     = 8;
parameter [0:(MST_AMT*32)-1]    MST_WEIGHT          = {32'd5, 32'd3, 32'd2, 32'd1};
parameter                       MST_ID_W            = $clog2(MST_AMT);
parameter                       SLV_ID_W            = $clog2(SLV_AMT);
// Transaction configuration
parameter                       DATA_WIDTH          = 32;
parameter                       ADDR_WIDTH          = 32;
parameter                       TRANS_MST_ID_W      = 5;                            // Bus width of master transaction ID 
parameter                       TRANS_SLV_ID_W      = TRANS_MST_ID_W + MST_ID_W;    // Bus width of slave transaction ID
parameter                       TRANS_BURST_W       = 2;                            // Width of xBURST 
parameter                       TRANS_DATA_LEN_W    = 3;                            // Bus width of xLEN
parameter                       TRANS_DATA_SIZE_W   = 3;                            // Bus width of xSIZE
parameter                       TRANS_WR_RESP_W     = 2;
// Slave info configuration (address mapping mechanism)
parameter                       SLV_ID_MSB_IDX      = 30;
parameter                       SLV_ID_LSB_IDX      = 30;
// Dispatcher DATA depth configuration
parameter                       DSP_RDATA_DEPTH     = 16;

typedef struct {
    bit                           trans_wr_rd; // Write(1) / read(0) transaction
    // -- Ax channel
    bit [TRANS_MST_ID_W-1:0]      AxID;
    bit [TRANS_BURST_W-1:0]       AxBURST;
    bit [SLV_ID_W-1:0]            AxADDR_slv_id;
    bit [ADDR_WIDTH-SLV_ID_W-2:0] AxADDR_addr;
    bit [TRANS_DATA_LEN_W-1:0]    AxLEN;
    bit [TRANS_DATA_SIZE_W-1:0]   AxSIZE;
    // -- W channel
    bit [DATA_WIDTH-1:0]          WDATA  [`MAX_LENGTH];    // Maximum: 8-beat transaction
} trans_info;

typedef struct {
    bit                             trans_wr_rd; // Write(1) / read(0) transaction
    bit [TRANS_MST_ID_W-1:0]        AxID_m;
    bit [TRANS_SLV_ID_W-1:0]        AxID_s;
    bit [TRANS_BURST_W-1:0]         AxBURST;
    bit [SLV_ID_W-1:0]              AxADDR_slv_id;
    bit [ADDR_WIDTH-SLV_ID_W-2:0]   AxADDR_addr;
    bit [TRANS_DATA_LEN_W-1:0]      AxLEN;
    bit [TRANS_DATA_SIZE_W-1:0]     AxSIZE;
} Ax_info;
typedef struct {
    bit [DATA_WIDTH-1:0]            WDATA [`MAX_LENGTH];
} W_info;

typedef struct {
    bit [TRANS_SLV_ID_W-1:0]        BID;
    bit [TRANS_WR_RESP_W-1:0]       BRESP;
} B_info;

typedef struct {
    bit [TRANS_SLV_ID_W-1:0]        RID;
    bit [DATA_WIDTH-1:0]            RDATA   [`MAX_LENGTH];
    bit [TRANS_WR_RESP_W-1:0]       RRESP;
} R_info;
    
class m_trans_random #(int mode = `BURST_MODE, int trans_rate = 50);
    // Transaction rate
    rand    bit                             m_trans_avail;
    // Write(1) / read(0) transaction
    rand    bit                             m_trans_wr_rd;
    // Ax channel
    rand    bit [TRANS_MST_ID_W-1:0]        m_AxID;
    rand    bit [TRANS_BURST_W-1:0]         m_AxBURST;
    rand    bit [SLV_ID_W-1:0]              m_AxADDR_slv_id;
    rand    bit [ADDR_WIDTH-SLV_ID_W-2:0]   m_AxADDR_addr;
    rand    bit [TRANS_DATA_LEN_W-1:0]      m_AxLEN;
    rand    bit [TRANS_DATA_SIZE_W-1:0]     m_AxSIZE;
    // W channel
    rand    bit [DATA_WIDTH-1:0]            m_WDATA [`MAX_LENGTH];    // Maximum: 8 beats
    
    constraint m_trans{
        if(mode == `BURST_MODE) {
            m_trans_avail               == 1;
            m_trans_wr_rd               dist{0 :/ 1, 1:/ 1};
            m_AxBURST                   == 1;                 
            m_AxADDR_slv_id             dist{0 :/ 1, 1:/ 1};
            m_AxADDR_addr%(1<<m_AxSIZE) == 0;   // All transfers must be aligned
        }
        else if(mode == `ARBITRATION_MODE) {
        
            m_trans_avail   dist{0 :/ 100, 1:/ trans_rate};  // rate = trans_rate % 
            m_AxADDR_slv_id == 0;                            // Map to only 1 slave (slv_id == 0)                       
            m_trans_wr_rd   == 0;                            // Only read transaction
            m_AxSIZE        == 0;                            // Align transaciton
        }
        else if(mode == `BURST_MODE_WR) {
            m_trans_avail               == 1;
            m_trans_wr_rd               == 1;
            m_AxBURST                   == 1;                 
            m_AxADDR_slv_id             dist{0 :/ 1, 1:/ 1};
            m_AxADDR_addr%(1<<m_AxSIZE) == 0;   // All transfers must be aligned
        }
    }
endclass : m_trans_random


module axi_interconnect_tb;
    
    // Input declaration
    // -- Global signals
    logic                                   ACLK_i;
    logic                                   ARESETn_i;
    // -- To Master (slave interface of the interconnect)
    // ---- Write address channel
    wire    [TRANS_MST_ID_W*MST_AMT-1:0]    m_AWID_i;
    wire    [ADDR_WIDTH*MST_AMT-1:0]        m_AWADDR_i;
    wire    [TRANS_BURST_W*MST_AMT-1:0]     m_AWBURST_i;
    wire    [TRANS_DATA_LEN_W*MST_AMT-1:0]  m_AWLEN_i;
    wire    [TRANS_DATA_SIZE_W*MST_AMT-1:0] m_AWSIZE_i;
    wire    [MST_AMT-1:0]                   m_AWVALID_i;
    // ---- Write data channel
    wire    [DATA_WIDTH*MST_AMT-1:0]        m_WDATA_i;
    wire    [MST_AMT-1:0]                   m_WLAST_i;
    wire    [MST_AMT-1:0]                   m_WVALID_i;
    // ---- Write response channel
    wire    [MST_AMT-1:0]                   m_BREADY_i;
    // ---- Read address channel
    wire    [TRANS_MST_ID_W*MST_AMT-1:0]    m_ARID_i;
    wire    [ADDR_WIDTH*MST_AMT-1:0]        m_ARADDR_i;
    wire    [TRANS_BURST_W*MST_AMT-1:0]     m_ARBURST_i;
    wire    [TRANS_DATA_LEN_W*MST_AMT-1:0]  m_ARLEN_i;
    wire    [TRANS_DATA_SIZE_W*MST_AMT-1:0] m_ARSIZE_i;
    wire    [MST_AMT-1:0]                   m_ARVALID_i;
    // ---- Read data channel
    wire    [MST_AMT-1:0]                   m_RREADY_i;
    // -- To slave (master interface of the interconnect)
    // ---- Write address channel (master)
    wire    [SLV_AMT-1:0]                   s_AWREADY_i;
    // ---- Write data channel (master)
    wire    [SLV_AMT-1:0]                   s_WREADY_i;
    // ---- Write response channel (master)
    wire    [TRANS_SLV_ID_W*SLV_AMT-1:0]    s_BID_i;
    wire    [TRANS_WR_RESP_W*SLV_AMT-1:0]   s_BRESP_i;
    wire    [SLV_AMT-1:0]                   s_BVALID_i;
    // ---- Read address channel (master)
    wire    [SLV_AMT-1:0]                   s_ARREADY_i;
    // ---- Read data channel (master)
    wire    [TRANS_SLV_ID_W*SLV_AMT-1:0]    s_RID_i;
    wire    [DATA_WIDTH*SLV_AMT-1:0]        s_RDATA_i;
    wire    [TRANS_WR_RESP_W*SLV_AMT-1:0]   s_RRESP_i;
    wire    [SLV_AMT-1:0]                   s_RLAST_i;
    wire    [SLV_AMT-1:0]                   s_RVALID_i;
    
    // Output declaration
    // -- To Master (slave interface of interconnect)
    // ---- Write address channel (master)
    wire    [MST_AMT-1:0]                   m_AWREADY_o;
    // ---- Write data channel (master)
    wire    [MST_AMT-1:0]                   m_WREADY_o;
    // ---- Write response channel (master)
    wire    [TRANS_MST_ID_W*MST_AMT-1:0]    m_BID_o;
    wire    [TRANS_WR_RESP_W*MST_AMT-1:0]   m_BRESP_o;
    wire    [MST_AMT-1:0]                   m_BVALID_o;
    // ---- Read address channel (master)
    wire    [MST_AMT-1:0]                   m_ARREADY_o;
    // ---- Read data channel (master)
    wire    [TRANS_MST_ID_W*MST_AMT-1:0]    m_RID_o;
    wire    [DATA_WIDTH*MST_AMT-1:0]        m_RDATA_o;
    wire    [TRANS_WR_RESP_W*MST_AMT-1:0]   m_RRESP_o;
    wire    [MST_AMT-1:0]                   m_RLAST_o;
    wire    [MST_AMT-1:0]                   m_RVALID_o;
    // -- To slave (master interface of the interconnect)
    // ---- Write address channel
    wire    [TRANS_SLV_ID_W*SLV_AMT-1:0]    s_AWID_o;
    wire    [ADDR_WIDTH*SLV_AMT-1:0]        s_AWADDR_o;
    wire    [TRANS_BURST_W*SLV_AMT-1:0]     s_AWBURST_o;
    wire    [TRANS_DATA_LEN_W*SLV_AMT-1:0]  s_AWLEN_o;
    wire    [TRANS_DATA_SIZE_W*SLV_AMT-1:0] s_AWSIZE_o;
    wire    [SLV_AMT-1:0]                   s_AWVALID_o;
    // ---- Write data channel
    wire    [DATA_WIDTH*SLV_AMT-1:0]        s_WDATA_o;
    wire    [SLV_AMT-1:0]                   s_WLAST_o;
    wire    [SLV_AMT-1:0]                   s_WVALID_o;
    // ---- Write response channel          
    wire    [SLV_AMT-1:0]                   s_BREADY_o;
    // ---- Read address channel            
    wire    [TRANS_SLV_ID_W*SLV_AMT-1:0]    s_ARID_o;
    wire    [ADDR_WIDTH*SLV_AMT-1:0]        s_ARADDR_o;
    wire    [TRANS_BURST_W*SLV_AMT-1:0]     s_ARBURST_o;
    wire    [TRANS_DATA_LEN_W*SLV_AMT-1:0]  s_ARLEN_o;
    wire    [TRANS_DATA_SIZE_W*SLV_AMT-1:0] s_ARSIZE_o;
    wire    [SLV_AMT-1:0]                   s_ARVALID_o;
    // ---- Read data channel
    wire    [SLV_AMT-1:0]                   s_RREADY_o;
    
    
    // Internal variable declaration
    genvar mst_idx;
    genvar slv_idx;
    
    // Internal signal declaration
    // -- To Master
    // -- -- Input
    // -- -- -- Write address channel
    reg     [TRANS_MST_ID_W-1:0]    m_AWID      [MST_AMT-1:0];
    reg     [ADDR_WIDTH-1:0]        m_AWADDR    [MST_AMT-1:0];
    reg     [TRANS_BURST_W-1:0]     m_AWBURST   [MST_AMT-1:0];
    reg     [TRANS_DATA_LEN_W-1:0]  m_AWLEN     [MST_AMT-1:0];
    reg     [TRANS_DATA_SIZE_W-1:0] m_AWSIZE    [MST_AMT-1:0];
    reg                             m_AWVALID   [MST_AMT-1:0];
    // -- -- -- Write data channel
    reg     [DATA_WIDTH-1:0]        m_WDATA     [MST_AMT-1:0];
    reg                             m_WLAST     [MST_AMT-1:0];
    reg                             m_WVALID    [MST_AMT-1:0];
    // -- -- -- Write response channel
    reg                             m_BREADY    [MST_AMT-1:0];
    // -- -- -- Read address channel
    reg     [TRANS_MST_ID_W-1:0]    m_ARID      [MST_AMT-1:0];
    reg     [ADDR_WIDTH-1:0]        m_ARADDR    [MST_AMT-1:0];
    reg     [TRANS_BURST_W-1:0]     m_ARBURST   [MST_AMT-1:0];
    reg     [TRANS_DATA_LEN_W-1:0]  m_ARLEN     [MST_AMT-1:0];
    reg     [TRANS_DATA_SIZE_W-1:0] m_ARSIZE    [MST_AMT-1:0];
    reg                             m_ARVALID   [MST_AMT-1:0];
    // -- -- -- Read data channel
    reg                             m_RREADY    [MST_AMT-1:0];
    // -- -- Output
    // -- -- -- Write address channel (master)
    wire                            m_AWREADY   [MST_AMT-1:0];
    // -- -- -- Write data channel (master)
    wire                            m_WREADY    [MST_AMT-1:0];
    // -- -- -- Write response channel (master)
    wire    [TRANS_MST_ID_W-1:0]    m_BID       [MST_AMT-1:0];
    wire    [TRANS_WR_RESP_W-1:0]   m_BRESP     [MST_AMT-1:0];
    wire                            m_BVALID    [MST_AMT-1:0];
    // -- -- -- Read address channel (master)
    wire                            m_ARREADY   [MST_AMT-1:0];
    // -- -- -- Read data channel (master)
    wire    [TRANS_MST_ID_W-1:0]    m_RID       [MST_AMT-1:0];
    wire    [DATA_WIDTH-1:0]        m_RDATA     [MST_AMT-1:0];
    wire    [TRANS_WR_RESP_W-1:0]   m_RRESP     [MST_AMT-1:0];
    wire                            m_RLAST     [MST_AMT-1:0];
    wire                            m_RVALID    [MST_AMT-1:0];
    // -- To Slave
    // -- -- Input
    // -- -- -- Write address channel (master)
    reg                             s_AWREADY   [SLV_AMT-1:0];
    // -- -- -- Write data channel (master)
    reg                             s_WREADY    [SLV_AMT-1:0];
    // -- -- -- Write response channel (master)
    reg     [TRANS_SLV_ID_W-1:0]    s_BID       [SLV_AMT-1:0];
    reg     [TRANS_WR_RESP_W-1:0]   s_BRESP     [SLV_AMT-1:0];
    reg                             s_BVALID    [SLV_AMT-1:0];
    // -- -- -- Read address channel (master)
    reg                             s_ARREADY   [SLV_AMT-1:0];
    // -- -- -- Read data channel (master)
    reg     [TRANS_SLV_ID_W-1:0]    s_RID       [SLV_AMT-1:0];
    reg     [DATA_WIDTH-1:0]        s_RDATA     [SLV_AMT-1:0];
    reg     [TRANS_WR_RESP_W-1:0]   s_RRESP     [SLV_AMT-1:0];
    reg                             s_RLAST     [SLV_AMT-1:0];
    reg                             s_RVALID    [SLV_AMT-1:0];
    // -- -- Output
    // -- -- -- Write address channel
    wire    [TRANS_SLV_ID_W-1:0]    s_AWID      [SLV_AMT-1:0];
    wire    [ADDR_WIDTH-1:0]        s_AWADDR    [SLV_AMT-1:0];
    wire    [TRANS_BURST_W-1:0]     s_AWBURST   [SLV_AMT-1:0];
    wire    [TRANS_DATA_LEN_W-1:0]  s_AWLEN     [SLV_AMT-1:0];
    wire    [TRANS_DATA_SIZE_W-1:0] s_AWSIZE    [SLV_AMT-1:0];
    wire                            s_AWVALID   [SLV_AMT-1:0];
    // -- -- -- Write data channel
    wire    [DATA_WIDTH-1:0]        s_WDATA     [SLV_AMT-1:0];
    wire                            s_WLAST     [SLV_AMT-1:0];
    wire                            s_WVALID    [SLV_AMT-1:0];
    // -- -- -- Write response channel          
    wire                            s_BREADY    [SLV_AMT-1:0];
    // -- -- -- Read address channel            
    wire    [TRANS_SLV_ID_W-1:0]    s_ARID      [SLV_AMT-1:0];
    wire    [ADDR_WIDTH-1:0]        s_ARADDR    [SLV_AMT-1:0];
    wire    [TRANS_BURST_W-1:0]     s_ARBURST   [SLV_AMT-1:0];
    wire    [TRANS_DATA_LEN_W-1:0]  s_ARLEN     [SLV_AMT-1:0];
    wire    [TRANS_DATA_SIZE_W-1:0] s_ARSIZE    [SLV_AMT-1:0];
    wire                            s_ARVALID   [SLV_AMT-1:0];
    // -- -- -- Read data channel
    wire                            s_RREADY    [SLV_AMT-1:0];
    
    generate
        // -- To Master
        for(mst_idx = 0; mst_idx < MST_AMT; mst_idx = mst_idx + 1) begin
            // -- -- Input
            assign m_AWID_i[TRANS_MST_ID_W*(mst_idx+1)-1-:TRANS_MST_ID_W]        = m_AWID[mst_idx];
            assign m_AWADDR_i[ADDR_WIDTH*(mst_idx+1)-1-:ADDR_WIDTH]              = m_AWADDR[mst_idx];
            assign m_AWBURST_i[TRANS_BURST_W*(mst_idx+1)-1-:TRANS_BURST_W]       = m_AWBURST[mst_idx];
            assign m_AWLEN_i[TRANS_DATA_LEN_W*(mst_idx+1)-1-:TRANS_DATA_LEN_W]   = m_AWLEN[mst_idx];
            assign m_AWSIZE_i[TRANS_DATA_SIZE_W*(mst_idx+1)-1-:TRANS_DATA_SIZE_W]= m_AWSIZE[mst_idx];
            assign m_AWVALID_i[mst_idx]                                          = m_AWVALID[mst_idx];
            assign m_WDATA_i[DATA_WIDTH*(mst_idx+1)-1-:DATA_WIDTH]               = m_WDATA[mst_idx];
            assign m_WLAST_i[mst_idx]                                            = m_WLAST[mst_idx];
            assign m_WVALID_i[mst_idx]                                           = m_WVALID[mst_idx];
            assign m_BREADY_i[mst_idx]                                           = m_BREADY[mst_idx];
            assign m_ARID_i[TRANS_MST_ID_W*(mst_idx+1)-1-:TRANS_MST_ID_W]        = m_ARID[mst_idx];
            assign m_ARADDR_i[ADDR_WIDTH*(mst_idx+1)-1-:ADDR_WIDTH]              = m_ARADDR[mst_idx];
            assign m_ARBURST_i[TRANS_BURST_W*(mst_idx+1)-1-:TRANS_BURST_W]       = m_ARBURST[mst_idx];
            assign m_ARLEN_i[TRANS_DATA_LEN_W*(mst_idx+1)-1-:TRANS_DATA_LEN_W]   = m_ARLEN[mst_idx];
            assign m_ARSIZE_i[TRANS_DATA_SIZE_W*(mst_idx+1)-1-:TRANS_DATA_SIZE_W]= m_ARSIZE[mst_idx];
            assign m_ARVALID_i[mst_idx]                                          = m_ARVALID[mst_idx];
            assign m_RREADY_i[mst_idx]                                           = m_RREADY[mst_idx];
            // -- -- Output
            assign m_AWREADY[mst_idx]                                           =  m_AWREADY_o[mst_idx];
            assign m_WREADY[mst_idx]                                            =  m_WREADY_o[mst_idx];
            assign m_BID[mst_idx]                                               =  m_BID_o[TRANS_MST_ID_W*(mst_idx+1)-1-:TRANS_MST_ID_W];   
            assign m_BRESP[mst_idx]                                             =  m_BRESP_o[TRANS_WR_RESP_W*(mst_idx+1)-1-:TRANS_WR_RESP_W]; 
            assign m_BVALID[mst_idx]                                            =  m_BVALID_o[mst_idx];
            assign m_ARREADY[mst_idx]                                           =  m_ARREADY_o[mst_idx];
            assign m_RID[mst_idx]                                               =  m_RID_o[TRANS_MST_ID_W*(mst_idx+1)-1-:TRANS_MST_ID_W];   
            assign m_RDATA[mst_idx]                                             =  m_RDATA_o[DATA_WIDTH*(mst_idx+1)-1-:DATA_WIDTH]; 
            assign m_RRESP[mst_idx]                                             =  m_RRESP_o[TRANS_WR_RESP_W*(mst_idx+1)-1-:TRANS_WR_RESP_W]; 
            assign m_RLAST[mst_idx]                                             =  m_RLAST_o[mst_idx]; 
            assign m_RVALID[mst_idx]                                            =  m_RVALID_o[mst_idx];
        end
        // -- To Slave
        for(slv_idx = 0; slv_idx < SLV_AMT; slv_idx = slv_idx + 1) begin
            // -- -- Input
            assign s_AWREADY_i[slv_idx]                                         = s_AWREADY[slv_idx];
            assign s_WREADY_i[slv_idx]                                          = s_WREADY[slv_idx];
            assign s_BID_i[TRANS_SLV_ID_W*(slv_idx+1)-1-:TRANS_SLV_ID_W]        = s_BID[slv_idx];
            assign s_BRESP_i[TRANS_WR_RESP_W*(slv_idx+1)-1-:TRANS_WR_RESP_W]    = s_BRESP[slv_idx];
            assign s_BVALID_i[slv_idx]                                          = s_BVALID[slv_idx];
            assign s_ARREADY_i[slv_idx]                                         = s_ARREADY[slv_idx];
            assign s_RID_i[TRANS_SLV_ID_W*(slv_idx+1)-1-:TRANS_SLV_ID_W]        = s_RID[slv_idx];
            assign s_RDATA_i[DATA_WIDTH*(slv_idx+1)-1-:DATA_WIDTH]              = s_RDATA[slv_idx];
            assign s_RRESP_i[TRANS_WR_RESP_W*(slv_idx+1)-1-:TRANS_WR_RESP_W]    = s_RRESP[slv_idx];
            assign s_RLAST_i[slv_idx]                                           = s_RLAST[slv_idx];
            assign s_RVALID_i[slv_idx]                                          = s_RVALID[slv_idx];
            // -- -- Output
            assign s_AWID[slv_idx]                                              = s_AWID_o[TRANS_SLV_ID_W*(slv_idx+1)-1-:TRANS_SLV_ID_W];
            assign s_AWADDR[slv_idx]                                            = s_AWADDR_o[ADDR_WIDTH*(slv_idx+1)-1-:ADDR_WIDTH];
            assign s_AWBURST[slv_idx]                                           = s_AWBURST_o[TRANS_BURST_W*(slv_idx+1)-1-:TRANS_BURST_W];
            assign s_AWLEN[slv_idx]                                             = s_AWLEN_o[TRANS_DATA_LEN_W*(slv_idx+1)-1-:TRANS_DATA_LEN_W];
            assign s_AWSIZE[slv_idx]                                            = s_AWSIZE_o[TRANS_DATA_SIZE_W*(slv_idx+1)-1-:TRANS_DATA_SIZE_W];
            assign s_AWVALID[slv_idx]                                           = s_AWVALID_o[slv_idx];
            assign s_WDATA[slv_idx]                                             = s_WDATA_o[DATA_WIDTH*(slv_idx+1)-1-:DATA_WIDTH];
            assign s_WLAST[slv_idx]                                             = s_WLAST_o[slv_idx];
            assign s_WVALID[slv_idx]                                            = s_WVALID_o[slv_idx];
            assign s_BREADY[slv_idx]                                            = s_BREADY_o[slv_idx];
            assign s_ARID[slv_idx]                                              = s_ARID_o[TRANS_SLV_ID_W*(slv_idx+1)-1-:TRANS_SLV_ID_W];
            assign s_ARADDR[slv_idx]                                            = s_ARADDR_o[ADDR_WIDTH*(slv_idx+1)-1-:ADDR_WIDTH];
            assign s_ARBURST[slv_idx]                                           = s_ARBURST_o[TRANS_BURST_W*(slv_idx+1)-1-:TRANS_BURST_W];
            assign s_ARLEN[slv_idx]                                             = s_ARLEN_o[TRANS_DATA_LEN_W*(slv_idx+1)-1-:TRANS_DATA_LEN_W];
            assign s_ARSIZE[slv_idx]                                            = s_ARSIZE_o[TRANS_DATA_SIZE_W*(slv_idx+1)-1-:TRANS_DATA_SIZE_W];
            assign s_ARVALID[slv_idx]                                           = s_ARVALID_o[slv_idx];
            assign s_RREADY[slv_idx]                                            = s_RREADY_o[slv_idx];
        end
    endgenerate
    
    
    axi_interconnect #(
        .MST_AMT(MST_AMT),
        .SLV_AMT(SLV_AMT),
        .OUTSTANDING_AMT(OUTSTANDING_AMT),
        .MST_WEIGHT(MST_WEIGHT),
        .MST_ID_W(MST_ID_W),
        .SLV_ID_W(SLV_ID_W),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .TRANS_MST_ID_W(TRANS_MST_ID_W),
        .TRANS_SLV_ID_W(TRANS_SLV_ID_W),
        .TRANS_BURST_W(TRANS_BURST_W),
        .TRANS_DATA_LEN_W(TRANS_DATA_LEN_W),
        .TRANS_DATA_SIZE_W(TRANS_DATA_SIZE_W),
        .TRANS_WR_RESP_W(TRANS_WR_RESP_W),
        .SLV_ID_MSB_IDX(SLV_ID_MSB_IDX),
        .SLV_ID_LSB_IDX(SLV_ID_LSB_IDX),
        .DSP_RDATA_DEPTH(DSP_RDATA_DEPTH)
    ) dut (
        .ACLK_i(ACLK_i),
        .ARESETn_i(ARESETn_i),
        .m_AWID_i(m_AWID_i),
        .m_AWADDR_i(m_AWADDR_i),
        .m_AWBURST_i(m_AWBURST_i),
        .m_AWLEN_i(m_AWLEN_i),
        .m_AWSIZE_i(m_AWSIZE_i),
        .m_AWVALID_i(m_AWVALID_i),
        .m_WDATA_i(m_WDATA_i),
        .m_WLAST_i(m_WLAST_i),
        .m_WVALID_i(m_WVALID_i),
        .m_BREADY_i(m_BREADY_i),
        .m_ARID_i(m_ARID_i),
        .m_ARADDR_i(m_ARADDR_i),
        .m_ARBURST_i(m_ARBURST_i),
        .m_ARLEN_i(m_ARLEN_i),
        .m_ARSIZE_i(m_ARSIZE_i),
        .m_ARVALID_i(m_ARVALID_i),
        .m_RREADY_i(m_RREADY_i),
        .s_AWREADY_i(s_AWREADY_i),
        .s_WREADY_i(s_WREADY_i),
        .s_BID_i(s_BID_i),
        .s_BRESP_i(s_BRESP_i),
        .s_BVALID_i(s_BVALID_i),
        .s_ARREADY_i(s_ARREADY_i),
        .s_RID_i(s_RID_i),
        .s_RDATA_i(s_RDATA_i),
        .s_RRESP_i(s_RRESP_i),
        .s_RLAST_i(s_RLAST_i),
        .s_RVALID_i(s_RVALID_i),
        .m_AWREADY_o(m_AWREADY_o),
        .m_WREADY_o(m_WREADY_o),
        .m_BID_o(m_BID_o),
        .m_BRESP_o(m_BRESP_o),
        .m_BVALID_o(m_BVALID_o),
        .m_ARREADY_o(m_ARREADY_o),
        .m_RID_o(m_RID_o),
        .m_RDATA_o(m_RDATA_o),
        .m_RRESP_o(m_RRESP_o),
        .m_RLAST_o(m_RLAST_o),
        .m_RVALID_o(m_RVALID_o),
        .s_AWID_o(s_AWID_o),
        .s_AWADDR_o(s_AWADDR_o),
        .s_AWBURST_o(s_AWBURST_o),
        .s_AWLEN_o(s_AWLEN_o),
        .s_AWSIZE_o(s_AWSIZE_o),
        .s_AWVALID_o(s_AWVALID_o),
        .s_WDATA_o(s_WDATA_o),
        .s_WLAST_o(s_WLAST_o),
        .s_WVALID_o(s_WVALID_o),
        .s_BREADY_o(s_BREADY_o),
        .s_ARID_o(s_ARID_o),
        .s_ARADDR_o(s_ARADDR_o),
        .s_ARBURST_o(s_ARBURST_o),
        .s_ARLEN_o(s_ARLEN_o),
        .s_ARSIZE_o(s_ARSIZE_o),
        .s_ARVALID_o(s_ARVALID_o),
        .s_RREADY_o(s_RREADY_o)
    );
    
    initial begin
        ACLK_i <= 0;
        forever #1 ACLK_i <= ~ACLK_i;
    end
    
    initial begin
        ARESETn_i <= 0;#5; ARESETn_i <= 1;
    end
    
    int idx = 0;
    initial begin : INIT_VALUE_BLOCK
        for(idx = 0; idx < MST_AMT; idx = idx + 1) begin
            // R
            m_ARID[idx]     <= 0;
            m_ARADDR[idx]   <= 0;
            m_ARBURST[idx]  <= 0;
            m_ARLEN[idx]    <= 0;
            m_ARSIZE[idx]   <= 0;
            m_ARVALID[idx]  <= 0;
            m_RREADY[idx]   <= 1'b1;
            // W
            m_AWID[idx]     <= 0;
            m_AWADDR[idx]   <= 0;
            m_AWBURST[idx]  <= 0;
            m_AWLEN[idx]    <= 0;
            m_AWSIZE[idx]   <= 0;
            m_AWVALID[idx]  <= 0;
            m_WDATA[idx]    <= 0;
            m_WLAST[idx]    <= 0;
            m_WVALID[idx]   <= 0;
            m_BREADY[idx]   <= 1'b1;
        end
        for(idx = 0; idx < SLV_AMT; idx = idx + 1) begin
            s_AWREADY[idx]  <= 1'b1;
            s_WREADY[idx]   <= 1'b1;
            s_BID[idx]      <= 0;
            s_BRESP[idx]    <= 0;
            s_BVALID[idx]   <= 0;
            s_ARREADY[idx]  <= 1'b1;
            s_RID[idx]      <= 0;
            s_RDATA[idx]    <= 0;
            s_RLAST[idx]    <= 0;
            s_RVALID[idx]   <= 0;
        end
    end
    // Queue declaration
    Ax_info     m_AW_queue  [MST_AMT][$];
    W_info      m_W_queue   [MST_AMT][$];
    B_info      m_B_queue   [MST_AMT][$];
    Ax_info     m_AR_queue  [MST_AMT][$];
    
    B_info      m_W_B_queue [MST_AMT][$];
    
    // -- -- -- -- -- -- --  Sequencer  -- -- -- -- -- -- -- 
    initial begin : SEQUENCER_0
        localparam mst_id = 0;
        #10;
        sequencer(mst_id);
    end
//    initial begin : SEQUENCER_1
//        localparam mst_id = 1;
//        #10;
//        sequencer(mst_id);
//    end
//    initial begin : SEQUENCER_2
//        localparam mst_id = 2;
//        #10;
//        sequencer(mst_id);
//    end
//    initial begin : SEQUENCER_3
//        localparam mst_id = 3;
//        #10;
//        sequencer(mst_id);
//    end
    // -- -- -- -- -- -- --  Sequencer  -- -- -- -- -- -- -- 
    
    // -- -- -- -- -- -- -- Master Driver -- -- -- -- -- -- -- 
    initial begin   : MASTER_DRIVER_0
        localparam mst_id = 0;
        #10;
        master_driver(mst_id);
    end
//    initial begin   : MASTER_DRIVER_1
//        localparam mst_id = 1;
//        #10;
//        master_driver(mst_id);
//    end
//    initial begin   : MASTER_DRIVER_2
//        localparam mst_id = 2;
//        #10;
//        master_driver(mst_id);
//    end
//    initial begin   : MASTER_DRIVER_3
//        localparam mst_id = 3;
//        #10;
//        master_driver(mst_id);
//    end
    // -- -- -- -- -- -- -- Master Driver -- -- -- -- -- -- -- 
    
    // -- -- -- -- -- -- --  Slave Driver -- -- -- -- -- -- -- 
    initial begin   : SLAVE_DRIVER_0
        localparam slv_id = 0;
        #10;
        slave_driver(slv_id);
    end
    initial begin   : SLAVE_DRIVER_1
        localparam slv_id = 1;
        #10;
        slave_driver(slv_id);
    end
    // -- -- -- -- -- -- --  Slave Driver -- -- -- -- -- -- -- 
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    // ------- DeepCode :v ------------
    
    // Transaction generator
    // -- Sequencer
    m_trans_random #(`BURST_MODE_WR) master_trans_gen [MST_AMT];
    // -- Packet
    // -- -- Packet to Master Driver (mailbox)
    mailbox #(Ax_info)  pck_AW_queue    [MST_AMT];
    mailbox #(W_info)   pck_W_queue     [MST_AMT];
    // -- -- Packet to Monitor (Queue)
    trans_info          pck_trans_queue [MST_AMT][$];
    // -- Master Driver
    // -- -- Write channel
    // -- -- -- AW to W
    mailbox #(Ax_info)  m_drv_AW_info   [MST_AMT];  // Store AWLEN
    // -- -- -- AW to B
    mailbox #(B_info)   m_drv_B_golden  [MST_AMT];  // BID == AWID, BRESP == 0
    // -- -- Read channel
    // -- -- -- AR to R
    mailbox #(Ax_info)  m_drv_AR_info   [MST_AMT];  // Store AWLEN
    mailbox #(R_info)   m_drv_R_golden  [MST_AMT];  // RID = ARID, RDATA[n] == (ARADDR + n*(2**AWSIZE)), RRESP == 0;
    // -- Slave Driver
    // -- -- Write channel
    mailbox #(Ax_info)  s_drv_AW_info   [MST_AMT];
    mailbox #(B_info)   s_drv_B_resp    [MST_AMT];
    // -- -- Read channel 
    
    task automatic sequencer (input int mst_id);
        // Temporary variable
        trans_info trans_temp;
        Ax_info Ax_temp;
        W_info W_temp;
        
        // Allocate new transaction generator
        master_trans_gen[mst_id]    = new();
        // -- Packet to Master driver (allocation)
        pck_AW_queue[mst_id]        = new(`NUM_TRANS);
        pck_W_queue[mst_id]         = new(`NUM_TRANS);
        
        for(int trans_num = 0; trans_num < `NUM_TRANS;) begin
            master_trans_gen[mst_id].randomize();
            if(master_trans_gen[mst_id].m_trans_avail == 1) begin
                trans_num = trans_num + 1;
                // Get info
                // -- Ax
                // -- -- Packet to Master driver
                Ax_temp.trans_wr_rd         = master_trans_gen[mst_id].m_trans_wr_rd;
                Ax_temp.AxID_m              = trans_num % OUTSTANDING_AMT;      // Different ID
                Ax_temp.AxBURST             = master_trans_gen[mst_id].m_AxBURST;
                Ax_temp.AxADDR_slv_id       = master_trans_gen[mst_id].m_AxADDR_slv_id;
                Ax_temp.AxADDR_addr         = master_trans_gen[mst_id].m_AxADDR_addr;
                Ax_temp.AxLEN               = master_trans_gen[mst_id].m_AxLEN;
                Ax_temp.AxSIZE              = master_trans_gen[mst_id].m_AxSIZE;
                // -- -- Packet to Monitor
                trans_temp.trans_wr_rd      = master_trans_gen[mst_id].m_trans_wr_rd;
                trans_temp.AxID             = trans_num % OUTSTANDING_AMT;      // Different ID
                trans_temp.AxBURST          = master_trans_gen[mst_id].m_AxBURST;
                trans_temp.AxADDR_slv_id    = master_trans_gen[mst_id].m_AxADDR_slv_id;
                trans_temp.AxADDR_addr      = master_trans_gen[mst_id].m_AxADDR_addr;
                trans_temp.AxLEN            = master_trans_gen[mst_id].m_AxLEN;
                trans_temp.AxSIZE           = master_trans_gen[mst_id].m_AxSIZE;
                // -- W 
                if(master_trans_gen[mst_id].m_trans_wr_rd == 1) begin : WR_TRANS_CASE
                    W_temp.WDATA            = master_trans_gen[mst_id].m_WDATA;
                    trans_temp.WDATA        = master_trans_gen[mst_id].m_WDATA;
                end 
                pck_AW_queue[mst_id].put(Ax_temp);
                pck_W_queue[mst_id].put(W_temp);
                pck_trans_queue[mst_id].push_back(trans_temp);
            end
            // Wait 1 cycle
            @(negedge ACLK_i);
        end
    endtask
    
    task automatic master_driver (input int mst_id);     
        int AW_started;
        int AW_completed;
        // Allocate
        m_drv_AW_info[mst_id]   = new();
        m_drv_B_golden[mst_id]  = new();
        m_drv_AR_info[mst_id]   = new();
        m_drv_R_golden[mst_id]  = new();
        fork
            begin   : Ax_channel
                Ax_info     Ax_temp;
                B_info      B_temp;
                R_info      R_temp;
                forever begin
                    if(pck_AW_queue[mst_id].try_get(Ax_temp)) begin
                        if(Ax_temp.trans_wr_rd == 1) begin : AW_transfer
                            m_AW_transfer(  
                                .mst_id (mst_id),
                                .AWID   (Ax_temp.AxID_m),  
                                .AWADDR ({0, Ax_temp.AxADDR_slv_id, Ax_temp.AxADDR_addr}),
                                .AWBURST(Ax_temp.AxBURST),
                                .AWLEN  (Ax_temp.AxLEN),
                                .AWSIZE (Ax_temp.AxSIZE)
                            );
                            // Restart other VALID
                            m_ARVALID[mst_id] <= 1'b0;
                            // Wait for Handshake occuring
                            wait(m_AWREADY[mst_id] == 1); #0.01;
                            // Expected B channel
                            B_temp.BID      =   Ax_temp.AxID_m;
                            B_temp.BRESP    =   0;  //  Only 'OKAY' 
                            // Store information
                            m_drv_AW_info[mst_id].put(Ax_temp);
                            m_drv_B_golden[mst_id].put(B_temp);
                        end
                        else begin : AR_transfer
                            m_AR_transfer(  
                                .mst_id (mst_id),
                                .ARID   (Ax_temp.AxID_m),  
                                .ARADDR ({0, Ax_temp.AxADDR_slv_id, Ax_temp.AxADDR_addr}),
                                .ARBURST(Ax_temp.AxBURST),
                                .ARLEN  (Ax_temp.AxLEN),
                                .ARSIZE (Ax_temp.AxSIZE)
                            );
                            // Restart other VALID
                            m_AWVALID[mst_id] <= 1'b0;
                            // Wait for Handshake occuring
                            wait(m_ARREADY[mst_id] == 1); #0.01;
                            // Expected R channel
                            R_temp.RID      = Ax_temp.AxID_m;
                            R_temp.RRESP    = 0;
                            for(int i = 0; i <= Ax_temp.AxLEN; i = i + 1) begin
                                R_temp.RDATA[i] = {1'b0, Ax_temp.AxADDR_slv_id, Ax_temp.AxADDR_addr} + i*(2**Ax_temp.AxSIZE);
                            end
                            // Store information
                            m_drv_AR_info[mst_id].put(Ax_temp);
                            m_drv_R_golden[mst_id].put(R_temp);
                        end
                    end
                    else begin
                        // Wait 1 cycle
                        @(posedge ACLK_i);
                        m_AWVALID[mst_id] <= 1'b0;
                        m_ARVALID[mst_id] <= 1'b0;
                    end
                end
            end
            begin   : W_channel
                Ax_info     Ax_temp;
                W_info      W_temp;
                forever begin
                    if(m_drv_AW_info[mst_id].try_get(Ax_temp)) begin
                        pck_W_queue[mst_id].get(W_temp);
                        // Generate WDATA 
                        for(int i = 0; i <= Ax_temp.AxLEN; i = i + 1) begin
                            m_W_transfer(
                                .mst_id(mst_id),
                                .WDATA({1'b0, Ax_temp.AxADDR_slv_id, Ax_temp.AxADDR_addr} + i*(2**Ax_temp.AxSIZE)), // WDATA[n] = AWADDR + n*SIZE
                                .WLAST(i == Ax_temp.AxLEN)
                            );
                            // Wait for Handshake occuring
                            wait(m_WREADY[mst_id] == 1); #0.01;
                        end
                    end
                    else begin
                        // Wait 1 cycle
                        @(posedge ACLK_i);
                        m_WVALID[mst_id] <= 1'b0;
                    end
                end
            end
            begin   : B_channel
                B_info  B_temp;
                B_info  B_sample;
                forever begin
                    if(m_drv_B_golden[mst_id].try_get(B_temp)) begin
                        // Assert BREADY
                        m_BREADY[mst_id] <= 1'b1;
                        m_B_receive (   
                            .mst_id(mst_id),
                            .BID(B_sample.BID),
                            .BRESP(B_sample.BRESP)
                        );
                        if(B_sample.BID == B_temp.BID && B_sample.BRESP == B_temp.BRESP) begin
                            $display("[PASS]: The transaction with BID = %d has completed", B_temp.BID);
                        end
                        else begin
                            $display("[FAIL]: Sample BID = %d and Golden BID = %d", B_sample.BID, B_temp.BID);
                            $finish;
                        end
                        // Handshake occurs
                        cl;
                    end
                    else begin
                        // Wait 1 cycle
                        @(posedge ACLK_i);
                        // Dessert BREADY
                        m_BREADY[mst_id] <= 1'b0;
                    end
                end
            end
            begin   : R_channel
                // Todo: 
            end 
        join_none
        $display("INFO: Master %d completed", mst_id);
    endtask 
   
    task automatic slave_driver (input int slv_id);
        s_drv_AW_info[slv_id]   = new();
        s_drv_B_resp[slv_id]    = new();
        fork
            begin   : AW_channel
                Ax_info AW_temp;
                bit     DMA_bit_temp;
                forever begin
                    s_AW_receive (
                        .slv_id (slv_id),
                        .AWID   (AW_temp.AxID_s),
                        .AWADDR ({DMA_bit_temp, AW_temp.AxADDR_slv_id, AW_temp.AxADDR_addr}),
                        .AWBURST(AW_temp.AxBURST),
                        .AWLEN  (AW_temp.AxLEN),
                        .AWSIZE (AW_temp.AxSIZE)
                    );
                    // Handshake occurs
                    cl;
                    // Store AW info 
                    s_drv_AW_info[slv_id].put(AW_temp);
                end
            end
            begin   : W_channel
                Ax_info AW_temp;
                W_info  W_temp;
                B_info  B_temp;
                bit     WLAST_temp;
                forever begin
                    if(s_drv_AW_info[slv_id].try_get(AW_temp)) begin
                        // Assert WREADY
                        s_WREADY[slv_id] = 1'b1;
                        for(int i = 0; i <= AW_temp.AxLEN; i = i + 1) begin
                            s_W_receive (
                                .slv_id(slv_id),
                                .WDATA(W_temp.WDATA[i]),
                                .WLAST(WLAST_temp)
                            );
                            // WDATA predictor
                            if(W_temp.WDATA[i] == {1'b0, AW_temp.AxADDR_slv_id, AW_temp.AxADDR_addr} + i*(2**AW_temp.AxSIZE)) begin
                                // Pass
                            end
                            else begin
                                $display("[FAIL]: W channel of Slave%d has receive wrong WDATA[%1d] %h (Expected WDATA: %h)", slv_id, i, W_temp.WDATA[i], {1'b0, AW_temp.AxADDR_slv_id, AW_temp.AxADDR_addr} + i*(2**AW_temp.AxSIZE));
                                $stop;
                            end
                            // WLAST predictor
                            if(WLAST_temp == (i == AW_temp.AxLEN)) begin
                            
                            end
                            else begin
                                $display("[FAIL]: W channel of Slave%d has receive wrong WLAST %d (idx: %d, AWLEN: %d)", slv_id, WLAST_temp, i, AW_temp.AxLEN);
                                $stop;
                            end
                            // Handshake occurs 
                            cl;
                        end
                        // Generate B transfer
                        B_temp.BID      = AW_temp.AxID_s;
                        B_temp.BRESP    = 0;
                        s_drv_B_resp[slv_id].put(B_temp);
                    end
                    else begin
                        // Wait 1 cycle
                        cl;
                        s_WREADY[slv_id] = 1'b0;
                    end
                end
            end
            begin   : B_channel
                B_info  B_temp;
                forever begin
                    if(s_drv_B_resp[slv_id].try_get(B_temp)) begin
                        s_B_transfer (
                            .slv_id(slv_id),
                            .BID(B_temp.BID),
                            .BRESP(B_temp.BRESP)
                        );
                        // Wait for handshaking
                        wait(s_BREADY[slv_id] == 1); #0.01;
                    end
                    else begin
                        // Wait 1 cycle
                        cl;
                        s_BVALID[slv_id] = 1'b0;
                    end
                end
            end
            begin   : AR_channel
                
            end
            begin   : R_channel
            
            end 
        join_none
    endtask
   
   
    task automatic cl;
        @(posedge ACLK_i); #0.01;
    endtask
    
    task automatic m_AR_transfer(
        input [MST_ID_W-1:0]            mst_id,
        input [TRANS_MST_ID_W-1:0]      ARID,
        input [ADDR_WIDTH-1:0]          ARADDR,
        input [TRANS_BURST_W-1:0]       ARBURST,
        input [TRANS_DATA_LEN_W-1:0]    ARLEN,
        input [TRANS_DATA_SIZE_W-1:0]   ARSIZE
    );
        cl;
        m_ARID[mst_id]     <= ARID;
        m_ARADDR[mst_id]   <= ARADDR;
        m_ARBURST[mst_id]  <= ARBURST;
        m_ARLEN[mst_id]    <= ARLEN;
        m_ARSIZE[mst_id]   <= ARSIZE;
        m_ARVALID[mst_id]  <= 1'b1;
    endtask
    
    task automatic m_AW_transfer(
        input [MST_ID_W-1:0]            mst_id,
        input [TRANS_MST_ID_W-1:0]      AWID,
        input [ADDR_WIDTH-1:0]          AWADDR,
        input [TRANS_BURST_W-1:0]       AWBURST,
        input [TRANS_DATA_LEN_W-1:0]    AWLEN,
        input [TRANS_DATA_SIZE_W-1:0]   AWSIZE
    );
        cl;
        m_AWID[mst_id]     <= AWID;
        m_AWADDR[mst_id]   <= AWADDR;
        m_AWBURST[mst_id]  <= AWBURST;
        m_AWLEN[mst_id]    <= AWLEN;
        m_AWSIZE[mst_id]   <= AWSIZE;
        m_AWVALID[mst_id]  <= 1'b1;
    endtask
    
    task automatic m_W_transfer (
        input [MST_ID_W-1:0]            mst_id,
        input [DATA_WIDTH-1:0]          WDATA,
        input                           WLAST
    );
        cl;
        m_WDATA[mst_id]     <= WDATA;
        m_WLAST[mst_id]     <= WLAST;
        m_WVALID[mst_id]    <= 1'b1;
    endtask
    
    task automatic m_B_receive (
        input       [MST_ID_W-1:0]          mst_id,
        output      [TRANS_SLV_ID_W-1:0]    BID,
        output      [TRANS_WR_RESP_W-1:0]   BRESP
    );
        // Wait for BVALID
        wait(m_BVALID[mst_id] == 1);
        #0.01;
        BID     = m_BID[mst_id];
        BRESP   = m_BRESP[mst_id];
    endtask
    
    task automatic s_AW_receive(
        input       [MST_ID_W-1:0]          slv_id,
        output      [TRANS_MST_ID_W-1:0]    AWID,
        output      [ADDR_WIDTH-1:0]        AWADDR,
        output      [TRANS_BURST_W-1:0]     AWBURST,
        output      [TRANS_DATA_LEN_W-1:0]  AWLEN,
        output      [TRANS_DATA_SIZE_W-1:0] AWSIZE
    );
        // Wait for BVALID
        wait(s_AWVALID[slv_id] == 1);
        #0.01;
        AWID    = s_AWID[slv_id];
        AWADDR  = s_AWADDR[slv_id];
        AWBURST = s_AWBURST[slv_id];
        AWLEN   = s_AWLEN[slv_id]; 
        AWSIZE  = s_AWSIZE[slv_id]; 
    endtask
    task automatic s_W_receive (
        input       [SLV_ID_W-1:0]        slv_id,
        output      [DATA_WIDTH-1:0]      WDATA,
        output                            WLAST
    );
        wait(s_WVALID[slv_id] == 1); #0.01;
        WDATA   = s_WDATA[slv_id];
        WLAST   = s_WLAST[slv_id];
    endtask
    task automatic s_B_transfer (
        input [SLV_ID_W-1:0]        slv_id,
        input [TRANS_SLV_ID_W-1:0]  BID,
        input [TRANS_WR_RESP_W-1:0] BRESP
    );
        cl;
        s_BID[slv_id]       <= BID;
        s_BRESP[slv_id]     <= BRESP;
        s_BVALID[slv_id]    <= 1'b1;
    endtask
    task automatic s_R_transfer (
        input [SLV_ID_W-1:0]            slv_id,
        input [TRANS_SLV_ID_W-1:0]      RID, 
        input [DATA_WIDTH-1:0]          RDATA,
        input                           RLAST
    );
        cl;
        s_RID[slv_id]       <= RID;
        s_RDATA[slv_id]     <= RDATA;
        s_RLAST[slv_id]     <= RLAST;
        s_RVALID[slv_id]    <= 1'b1;
    endtask
    
endmodule






