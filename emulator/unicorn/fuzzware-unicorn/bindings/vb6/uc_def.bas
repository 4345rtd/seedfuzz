Attribute VB_Name = "uc_def"
Option Explicit

'Unicorn Engine x86 32bit wrapper class for vb6

'Contributed by: FireEye FLARE team
'Author:         David Zimmer <david.zimmer@fireeye.com>, <dzzie@yahoo.com>
'License:        Apache

' supported api:
'        ucs_version
'        ucs_arch_supported
'        ucs_open
'        ucs_close
'        uc_reg_write
'        uc_reg_read
'        uc_mem_write
'        UC_MEM_READ
'        uc_emu_start
'        uc_emu_stop
'        ucs_hook_add
'        uc_mem_map
'        uc_hook_del
'        uc_mem_regions
'        uc_mem_map_ptr
'        uc_context_alloc
'        uc_free
'        uc_context_save
'        uc_context_restore
'        uc_mem_unmap
'        uc_mem_protect
'        uc_strerror
'        uc_errno

' supported hooks:
'        UC_HOOK_CODE
'        UC_HOOK_BLOCK
'        memory READ/WRITE/FETCH
'        invalid memory access
'        interrupts
'
' bonus:
'        disasm_addr     (32bit only uses libdasm)
'        mem_write_block (map and write data auto handles alignment)
'        get_memMap      (wrapper for uc_mem_regions)
'
'

'sample supports multiple instances, required since callbacks must be in a shared module
Global instances As New Collection
Global UNICORN_PATH As String
Global DYNLOAD As Long

Public Enum uc_arch
    UC_ARCH_ARM = 1    ' ARM architecture (including Thumb, Thumb-2)
    UC_ARCH_ARM64 = 2  ' ARM-64, also called AArch64okok
    UC_ARCH_MIPS = 3   ' Mips architecture
    UC_ARCH_X86 = 4    ' X86 architecture (including x86 & x86-64)
    UC_ARCH_PPC = 5    ' PowerPC architecture (currently unsupported)
    UC_ARCH_SPARC = 6  ' Sparc architecture
    UC_ARCH_M68K = 7   ' M68K architecture
    UC_ARCH_MAX = 8
End Enum

Public Enum uc_prot
   UC_PROT_NONE = 0
   UC_PROT_READ = 1
   UC_PROT_WRITE = 2
   UC_PROT_EXEC = 4
   UC_PROT_ALL = 7
End Enum

Public Enum uc_err
    uc_err_ok = 0               ' No error: everything was fine
    UC_ERR_NOMEM = 1            ' Out-Of-Memory error: uc_open(), uc_emulate()
    UC_ERR_ARCH = 2             ' Unsupported architecture: uc_open()
    UC_ERR_HANDLE = 3           ' Invalid handle
    UC_ERR_MODE = 4             ' Invalid/unsupported mode: uc_open()
    UC_ERR_VERSION = 5          ' Unsupported version (bindings)
    UC_ERR_READ_UNMAPPED = 6    ' Quit emulation due to READ on unmapped memory: uc_emu_start()
    UC_ERR_WRITE_UNMAPPED = 7   ' Quit emulation due to WRITE on unmapped memory: uc_emu_start()
    UC_ERR_FETCH_UNMAPPED = 8   ' Quit emulation due to FETCH on unmapped memory: uc_emu_start()
    UC_ERR_HOOK = 9             ' Invalid hook type: uc_hook_add()
    UC_ERR_INSN_INVALID = 10    ' Quit emulation due to invalid instruction: uc_emu_start()
    UC_ERR_MAP = 11             ' Invalid memory mapping: uc_mem_map()
    UC_ERR_WRITE_PROT = 12      ' Quit emulation due to UC_MEM_WRITE_PROT violation: uc_emu_start()
    UC_ERR_READ_PROT = 13       ' Quit emulation due to UC_MEM_READ_PROT violation: uc_emu_start()
    UC_ERR_FETCH_PROT = 14      ' Quit emulation due to UC_MEM_FETCH_PROT violation: uc_emu_start()
    UC_ERR_ARG = 15             ' Inavalid argument provided to uc_xxx function (See specific function API)
    UC_ERR_READ_UNALIGNED = 16  ' Unaligned read
    UC_ERR_WRITE_UNALIGNED = 17 ' Unaligned write
    UC_ERR_FETCH_UNALIGNED = 18 ' Unaligned fetch
    UC_ERR_HOOK_EXIST = 19      ' hook for this event already existed
    UC_ERR_RESOURCE = 20        ' Insufficient resource: uc_emu_start()
    UC_ERR_EXCEPTION = 21       ' Unhandled CPU exception
End Enum

' All type of memory accesses for UC_HOOK_MEM_*
Public Enum uc_mem_type
    UC_MEM_READ = 16           ' Memory is read from
    uc_mem_write = 17          ' Memory is written to
    UC_MEM_FETCH = 18          ' Memory is fetched
    UC_MEM_READ_UNMAPPED = 19  ' Unmapped memory is read from
    UC_MEM_WRITE_UNMAPPED = 20 ' Unmapped memory is written to
    UC_MEM_FETCH_UNMAPPED = 21 ' Unmapped memory is fetched
    UC_MEM_WRITE_PROT = 22     ' Write to write protected, but mapped, memory
    UC_MEM_READ_PROT = 23      ' Read from read protected, but mapped, memory
    UC_MEM_FETCH_PROT = 24     ' Fetch from non-executable, but mapped, memory
    UC_MEM_READ_AFTER = 25     ' Memory is read from (successful access)
End Enum

Public Enum uc_mode                   'from /bindings/dotnet/common.fs
     UC_MODE_LITTLE_ENDIAN = 0        'little-endian mode (default mode)
     UC_MODE_BIG_ENDIAN = 1073741824  'big-endian mode
'     UC_MODE_ARM = 0                  'ARM mode
'     UC_MODE_THUMB = 16               'THUMB mode (including Thumb-2)
'     UC_MODE_MCLASS = 32              'ARM's Cortex-M series (currently unsupported)
'     UC_MODE_V8 = 64                  'ARMv8 A32 encodings for ARM (currently unsupported)
'     UC_MODE_MICRO = 16               'MicroMips mode (currently unsupported)
'     UC_MODE_MIPS3 = 32               'Mips III ISA (currently unsupported)
'     UC_MODE_MIPS32R6 = 64            'Mips32r6 ISA (currently unsupported)
'     UC_MODE_MIPS32 = 4               'Mips32 ISA
'     UC_MODE_MIPS64 = 8               'Mips64 ISA
     UC_MODE_16 = 2                   '16-bit mode
     UC_MODE_32 = 4                   '32-bit mode
     UC_MODE_64 = 8                   '64-bit mode
'     UC_MODE_PPC32 = 4                '32-bit mode (currently unsupported)
'     UC_MODE_PPC64 = 8                '64-bit mode (currently unsupported)
'     UC_MODE_QPX = 16                 'Quad Processing eXtensions mode (currently unsupported)
'     UC_MODE_SPARC32 = 4              '32-bit mode
'     UC_MODE_SPARC64 = 8              '64-bit mode
'     UC_MODE_V9 = 16                  'SparcV9 mode (currently unsupported)
End Enum

Public Enum uc_hook_type              'from /bindings/dotnet/common.fs
     UC_HOOK_INTR = 1                 ' Hook all interrupt/syscall events
     UC_HOOK_INSN = 2                 ' Hook a particular instruction
     UC_HOOK_CODE = 4                 ' Hook a range of code
     UC_HOOK_BLOCK = 8                ' Hook basic blocks
     UC_HOOK_MEM_READ_UNMAPPED = 16   ' Hook for memory read on unmapped memory
     UC_HOOK_MEM_WRITE_UNMAPPED = 32  ' Hook for invalid memory write events
     UC_HOOK_MEM_FETCH_UNMAPPED = 64  ' Hook for invalid memory fetch for execution events
     UC_HOOK_MEM_READ_PROT = 128      ' Hook for memory read on read-protected memory
     UC_HOOK_MEM_WRITE_PROT = 256     ' Hook for memory write on write-protected memory
     UC_HOOK_MEM_FETCH_PROT = 512     ' Hook for memory fetch on non-executable memory
     UC_HOOK_MEM_READ = 1024          ' Hook memory read events.
     UC_HOOK_MEM_WRITE = 2048         ' Hook memory write events.
     UC_HOOK_MEM_FETCH = 4096         ' Hook memory fetch for execution events
     UC_HOOK_MEM_READ_AFTER = 8192    ' Hook memory read events, but only successful access.(triggered after successful read.)
     UC_HOOK_MEM_UNMAPPED = 112
     UC_HOOK_MEM_PROT = 896
     UC_HOOK_MEM_READ_INVALID = 144
     UC_HOOK_MEM_WRITE_INVALID = 288
     UC_HOOK_MEM_FETCH_INVALID = 576
     UC_HOOK_MEM_INVALID = 1008
     UC_HOOK_MEM_VALID = 7168
End Enum

Public Enum hookCatagory
    hc_code = 0
    hc_block = 1
    hc_inst = 2
    hc_int = 3
    hc_mem = 4
    hc_memInvalid = 5
End Enum

Public Enum uc_x86_reg
     UC_X86_REG_INVALID = 0
     UC_X86_REG_AH = 1
     UC_X86_REG_AL = 2
     UC_X86_REG_AX = 3
     UC_X86_REG_BH = 4
     UC_X86_REG_Bl = 5
     UC_X86_REG_BP = 6
     UC_X86_REG_BPL = 7
     UC_X86_REG_BX = 8
     UC_X86_REG_CH = 9
     UC_X86_REG_CL = 10
     UC_X86_REG_CS = 11
     UC_X86_REG_CX = 12
     UC_X86_REG_DH = 13
     UC_X86_REG_DI = 14
     UC_X86_REG_DIL = 15
     UC_X86_REG_DL = 16
     UC_X86_REG_DS = 17
     UC_X86_REG_DX = 18
     UC_X86_REG_EAX = 19
     UC_X86_REG_EBP = 20
     UC_X86_REG_EBX = 21
     UC_X86_REG_ECX = 22
     UC_X86_REG_EDI = 23
     UC_X86_REG_EDX = 24
     UC_X86_REG_EFLAGS = 25
     UC_X86_REG_EIP = 26
     UC_X86_REG_EIZ = 27
     UC_X86_REG_ES = 28
     UC_X86_REG_ESI = 29
     UC_X86_REG_ESP = 30
     UC_X86_REG_FPSW = 31
     UC_X86_REG_FS = 32
     UC_X86_REG_GS = 33
     UC_X86_REG_IP = 34
     UC_X86_REG_RAX = 35
     UC_X86_REG_RBP = 36
     UC_X86_REG_RBX = 37
     UC_X86_REG_RCX = 38
     UC_X86_REG_RDI = 39
     UC_X86_REG_RDX = 40
     UC_X86_REG_RIP = 41
     UC_X86_REG_RIZ = 42
     UC_X86_REG_RSI = 43
     UC_X86_REG_RSP = 44
     UC_X86_REG_SI = 45
     UC_X86_REG_SIL = 46
     UC_X86_REG_SP = 47
     UC_X86_REG_SPL = 48
     UC_X86_REG_SS = 49
     UC_X86_REG_CR0 = 50
     UC_X86_REG_CR1 = 51
     UC_X86_REG_CR2 = 52
     UC_X86_REG_CR3 = 53
     UC_X86_REG_CR4 = 54
     UC_X86_REG_CR5 = 55
     UC_X86_REG_CR6 = 56
     UC_X86_REG_CR7 = 57
     UC_X86_REG_CR8 = 58
     UC_X86_REG_CR9 = 59
     UC_X86_REG_CR10 = 60
     UC_X86_REG_CR11 = 61
     UC_X86_REG_CR12 = 62
     UC_X86_REG_CR13 = 63
     UC_X86_REG_CR14 = 64
     UC_X86_REG_CR15 = 65
     UC_X86_REG_DR0 = 66
     UC_X86_REG_DR1 = 67
     UC_X86_REG_DR2 = 68
     UC_X86_REG_DR3 = 69
     UC_X86_REG_DR4 = 70
     UC_X86_REG_DR5 = 71
     UC_X86_REG_DR6 = 72
     UC_X86_REG_DR7 = 73
     UC_X86_REG_DR8 = 74
     UC_X86_REG_DR9 = 75
     UC_X86_REG_DR10 = 76
     UC_X86_REG_DR11 = 77
     UC_X86_REG_DR12 = 78
     UC_X86_REG_DR13 = 79
     UC_X86_REG_DR14 = 80
     UC_X86_REG_DR15 = 81
     UC_X86_REG_FP0 = 82
     UC_X86_REG_FP1 = 83
     UC_X86_REG_FP2 = 84
     UC_X86_REG_FP3 = 85
     UC_X86_REG_FP4 = 86
     UC_X86_REG_FP5 = 87
     UC_X86_REG_FP6 = 88
     UC_X86_REG_FP7 = 89
     UC_X86_REG_K0 = 90
     UC_X86_REG_K1 = 91
     UC_X86_REG_K2 = 92
     UC_X86_REG_K3 = 93
     UC_X86_REG_K4 = 94
     UC_X86_REG_K5 = 95
     UC_X86_REG_K6 = 96
     UC_X86_REG_K7 = 97
     UC_X86_REG_MM0 = 98
     UC_X86_REG_MM1 = 99
     UC_X86_REG_MM2 = 100
     UC_X86_REG_MM3 = 101
     UC_X86_REG_MM4 = 102
     UC_X86_REG_MM5 = 103
     UC_X86_REG_MM6 = 104
     UC_X86_REG_MM7 = 105
     UC_X86_REG_R8 = 106
     UC_X86_REG_R9 = 107
     UC_X86_REG_R10 = 108
     UC_X86_REG_R11 = 109
     UC_X86_REG_R12 = 110
     UC_X86_REG_R13 = 111
     UC_X86_REG_R14 = 112
     UC_X86_REG_R15 = 113
     UC_X86_REG_ST0 = 114
     UC_X86_REG_ST1 = 115
     UC_X86_REG_ST2 = 116
     UC_X86_REG_ST3 = 117
     UC_X86_REG_ST4 = 118
     UC_X86_REG_ST5 = 119
     UC_X86_REG_ST6 = 120
     UC_X86_REG_ST7 = 121
     UC_X86_REG_XMM0 = 122
     UC_X86_REG_XMM1 = 123
     UC_X86_REG_XMM2 = 124
     UC_X86_REG_XMM3 = 125
     UC_X86_REG_XMM4 = 126
     UC_X86_REG_XMM5 = 127
     UC_X86_REG_XMM6 = 128
     UC_X86_REG_XMM7 = 129
     UC_X86_REG_XMM8 = 130
     UC_X86_REG_XMM9 = 131
     UC_X86_REG_XMM10 = 132
     UC_X86_REG_XMM11 = 133
     UC_X86_REG_XMM12 = 134
     UC_X86_REG_XMM13 = 135
     UC_X86_REG_XMM14 = 136
     UC_X86_REG_XMM15 = 137
     UC_X86_REG_XMM16 = 138
     UC_X86_REG_XMM17 = 139
     UC_X86_REG_XMM18 = 140
     UC_X86_REG_XMM19 = 141
     UC_X86_REG_XMM20 = 142
     UC_X86_REG_XMM21 = 143
     UC_X86_REG_XMM22 = 144
     UC_X86_REG_XMM23 = 145
     UC_X86_REG_XMM24 = 146
     UC_X86_REG_XMM25 = 147
     UC_X86_REG_XMM26 = 148
     UC_X86_REG_XMM27 = 149
     UC_X86_REG_XMM28 = 150
     UC_X86_REG_XMM29 = 151
     UC_X86_REG_XMM30 = 152
     UC_X86_REG_XMM31 = 153
     UC_X86_REG_YMM0 = 154
     UC_X86_REG_YMM1 = 155
     UC_X86_REG_YMM2 = 156
     UC_X86_REG_YMM3 = 157
     UC_X86_REG_YMM4 = 158
     UC_X86_REG_YMM5 = 159
     UC_X86_REG_YMM6 = 160
     UC_X86_REG_YMM7 = 161
     UC_X86_REG_YMM8 = 162
     UC_X86_REG_YMM9 = 163
     UC_X86_REG_YMM10 = 164
     UC_X86_REG_YMM11 = 165
     UC_X86_REG_YMM12 = 166
     UC_X86_REG_YMM13 = 167
     UC_X86_REG_YMM14 = 168
     UC_X86_REG_YMM15 = 169
     UC_X86_REG_YMM16 = 170
     UC_X86_REG_YMM17 = 171
     UC_X86_REG_YMM18 = 172
     UC_X86_REG_YMM19 = 173
     UC_X86_REG_YMM20 = 174
     UC_X86_REG_YMM21 = 175
     UC_X86_REG_YMM22 = 176
     UC_X86_REG_YMM23 = 177
     UC_X86_REG_YMM24 = 178
     UC_X86_REG_YMM25 = 179
     UC_X86_REG_YMM26 = 180
     UC_X86_REG_YMM27 = 181
     UC_X86_REG_YMM28 = 182
     UC_X86_REG_YMM29 = 183
     UC_X86_REG_YMM30 = 184
     UC_X86_REG_YMM31 = 185
     UC_X86_REG_ZMM0 = 186
     UC_X86_REG_ZMM1 = 187
     UC_X86_REG_ZMM2 = 188
     UC_X86_REG_ZMM3 = 189
     UC_X86_REG_ZMM4 = 190
     UC_X86_REG_ZMM5 = 191
     UC_X86_REG_ZMM6 = 192
     UC_X86_REG_ZMM7 = 193
     UC_X86_REG_ZMM8 = 194
     UC_X86_REG_ZMM9 = 195
     UC_X86_REG_ZMM10 = 196
     UC_X86_REG_ZMM11 = 197
     UC_X86_REG_ZMM12 = 198
     UC_X86_REG_ZMM13 = 199
     UC_X86_REG_ZMM14 = 200
     UC_X86_REG_ZMM15 = 201
     UC_X86_REG_ZMM16 = 202
     UC_X86_REG_ZMM17 = 203
     UC_X86_REG_ZMM18 = 204
     UC_X86_REG_ZMM19 = 205
     UC_X86_REG_ZMM20 = 206
     UC_X86_REG_ZMM21 = 207
     UC_X86_REG_ZMM22 = 208
     UC_X86_REG_ZMM23 = 209
     UC_X86_REG_ZMM24 = 210
     UC_X86_REG_ZMM25 = 211
     UC_X86_REG_ZMM26 = 212
     UC_X86_REG_ZMM27 = 213
     UC_X86_REG_ZMM28 = 214
     UC_X86_REG_ZMM29 = 215
     UC_X86_REG_ZMM30 = 216
     UC_X86_REG_ZMM31 = 217
     UC_X86_REG_R8B = 218
     UC_X86_REG_R9B = 219
     UC_X86_REG_R10B = 220
     UC_X86_REG_R11B = 221
     UC_X86_REG_R12B = 222
     UC_X86_REG_R13B = 223
     UC_X86_REG_R14B = 224
     UC_X86_REG_R15B = 225
     UC_X86_REG_R8D = 226
     UC_X86_REG_R9D = 227
     UC_X86_REG_R10D = 228
     UC_X86_REG_R11D = 229
     UC_X86_REG_R12D = 230
     UC_X86_REG_R13D = 231
     UC_X86_REG_R14D = 232
     UC_X86_REG_R15D = 233
     UC_X86_REG_R8W = 234
     UC_X86_REG_R9W = 235
     UC_X86_REG_R10W = 236
     UC_X86_REG_R11W = 237
     UC_X86_REG_R12W = 238
     UC_X86_REG_R13W = 239
     UC_X86_REG_R14W = 240
     UC_X86_REG_R15W = 241
     UC_X86_REG_IDTR = 242
     UC_X86_REG_GDTR = 243
     UC_X86_REG_LDTR = 244
     UC_X86_REG_TR = 245
     UC_X86_REG_FPCW = 246
     UC_X86_REG_FPTAG = 247
     UC_X86_REG_ENDING = 248
End Enum

'Public Enum uc_x86_insn
'     UC_X86_INS_INVALID = 0
'     UC_X86_INS_AAA = 1
'     UC_X86_INS_AAD = 2
'     UC_X86_INS_AAM = 3
'     UC_X86_INS_AAS = 4
'     UC_X86_INS_FABS = 5
'     UC_X86_INS_ADC = 6
'     UC_X86_INS_ADCX = 7
'     UC_X86_INS_ADD = 8
'     UC_X86_INS_ADDPD = 9
'     UC_X86_INS_ADDPS = 10
'     UC_X86_INS_ADDSD = 11
'     UC_X86_INS_ADDSS = 12
'     UC_X86_INS_ADDSUBPD = 13
'     UC_X86_INS_ADDSUBPS = 14
'     UC_X86_INS_FADD = 15
'     UC_X86_INS_FIADD = 16
'     UC_X86_INS_FADDP = 17
'     UC_X86_INS_ADOX = 18
'     UC_X86_INS_AESDECLAST = 19
'     UC_X86_INS_AESDEC = 20
'     UC_X86_INS_AESENCLAST = 21
'     UC_X86_INS_AESENC = 22
'     UC_X86_INS_AESIMC = 23
'     UC_X86_INS_AESKEYGENASSIST = 24
'     UC_X86_INS_AND = 25
'     UC_X86_INS_ANDN = 26
'     UC_X86_INS_ANDNPD = 27
'     UC_X86_INS_ANDNPS = 28
'     UC_X86_INS_ANDPD = 29
'     UC_X86_INS_ANDPS = 30
'     UC_X86_INS_ARPL = 31
'     UC_X86_INS_BEXTR = 32
'     UC_X86_INS_BLCFILL = 33
'     UC_X86_INS_BLCI = 34
'     UC_X86_INS_BLCIC = 35
'     UC_X86_INS_BLCMSK = 36
'     UC_X86_INS_BLCS = 37
'     UC_X86_INS_BLENDPD = 38
'     UC_X86_INS_BLENDPS = 39
'     UC_X86_INS_BLENDVPD = 40
'     UC_X86_INS_BLENDVPS = 41
'     UC_X86_INS_BLSFILL = 42
'     UC_X86_INS_BLSI = 43
'     UC_X86_INS_BLSIC = 44
'     UC_X86_INS_BLSMSK = 45
'     UC_X86_INS_BLSR = 46
'     UC_X86_INS_BOUND = 47
'     UC_X86_INS_BSF = 48
'     UC_X86_INS_BSR = 49
'     UC_X86_INS_BSWAP = 50
'     UC_X86_INS_BT = 51
'     UC_X86_INS_BTC = 52
'     UC_X86_INS_BTR = 53
'     UC_X86_INS_BTS = 54
'     UC_X86_INS_BZHI = 55
'     UC_X86_INS_CALL = 56
'     UC_X86_INS_CBW = 57
'     UC_X86_INS_CDQ = 58
'     UC_X86_INS_CDQE = 59
'     UC_X86_INS_FCHS = 60
'     UC_X86_INS_CLAC = 61
'     UC_X86_INS_CLC = 62
'     UC_X86_INS_CLD = 63
'     UC_X86_INS_CLFLUSH = 64
'     UC_X86_INS_CLFLUSHOPT = 65
'     UC_X86_INS_CLGI = 66
'     UC_X86_INS_CLI = 67
'     UC_X86_INS_CLTS = 68
'     UC_X86_INS_CLWB = 69
'     UC_X86_INS_CMC = 70
'     UC_X86_INS_CMOVA = 71
'     UC_X86_INS_CMOVAE = 72
'     UC_X86_INS_CMOVB = 73
'     UC_X86_INS_CMOVBE = 74
'     UC_X86_INS_FCMOVBE = 75
'     UC_X86_INS_FCMOVB = 76
'     UC_X86_INS_CMOVE = 77
'     UC_X86_INS_FCMOVE = 78
'     UC_X86_INS_CMOVG = 79
'     UC_X86_INS_CMOVGE = 80
'     UC_X86_INS_CMOVL = 81
'     UC_X86_INS_CMOVLE = 82
'     UC_X86_INS_FCMOVNBE = 83
'     UC_X86_INS_FCMOVNB = 84
'     UC_X86_INS_CMOVNE = 85
'     UC_X86_INS_FCMOVNE = 86
'     UC_X86_INS_CMOVNO = 87
'     UC_X86_INS_CMOVNP = 88
'     UC_X86_INS_FCMOVNU = 89
'     UC_X86_INS_CMOVNS = 90
'     UC_X86_INS_CMOVO = 91
'     UC_X86_INS_CMOVP = 92
'     UC_X86_INS_FCMOVU = 93
'     UC_X86_INS_CMOVS = 94
'     UC_X86_INS_CMP = 95
'     UC_X86_INS_CMPPD = 96
'     UC_X86_INS_CMPPS = 97
'     UC_X86_INS_CMPSB = 98
'     UC_X86_INS_CMPSD = 99
'     UC_X86_INS_CMPSQ = 100
'     UC_X86_INS_CMPSS = 101
'     UC_X86_INS_CMPSW = 102
'     UC_X86_INS_CMPXCHG16B = 103
'     UC_X86_INS_CMPXCHG = 104
'     UC_X86_INS_CMPXCHG8B = 105
'     UC_X86_INS_COMISD = 106
'     UC_X86_INS_COMISS = 107
'     UC_X86_INS_FCOMP = 108
'     UC_X86_INS_FCOMPI = 109
'     UC_X86_INS_FCOMI = 110
'     UC_X86_INS_FCOM = 111
'     UC_X86_INS_FCOS = 112
'     UC_X86_INS_CPUID = 113
'     UC_X86_INS_CQO = 114
'     UC_X86_INS_CRC32 = 115
'     UC_X86_INS_CVTDQ2PD = 116
'     UC_X86_INS_CVTDQ2PS = 117
'     UC_X86_INS_CVTPD2DQ = 118
'     UC_X86_INS_CVTPD2PS = 119
'     UC_X86_INS_CVTPS2DQ = 120
'     UC_X86_INS_CVTPS2PD = 121
'     UC_X86_INS_CVTSD2SI = 122
'     UC_X86_INS_CVTSD2SS = 123
'     UC_X86_INS_CVTSI2SD = 124
'     UC_X86_INS_CVTSI2SS = 125
'     UC_X86_INS_CVTSS2SD = 126
'     UC_X86_INS_CVTSS2SI = 127
'     UC_X86_INS_CVTTPD2DQ = 128
'     UC_X86_INS_CVTTPS2DQ = 129
'     UC_X86_INS_CVTTSD2SI = 130
'     UC_X86_INS_CVTTSS2SI = 131
'     UC_X86_INS_CWD = 132
'     UC_X86_INS_CWDE = 133
'     UC_X86_INS_DAA = 134
'     UC_X86_INS_DAS = 135
'     UC_X86_INS_DATA16 = 136
'     UC_X86_INS_DEC = 137
'     UC_X86_INS_DIV = 138
'     UC_X86_INS_DIVPD = 139
'     UC_X86_INS_DIVPS = 140
'     UC_X86_INS_FDIVR = 141
'     UC_X86_INS_FIDIVR = 142
'     UC_X86_INS_FDIVRP = 143
'     UC_X86_INS_DIVSD = 144
'     UC_X86_INS_DIVSS = 145
'     UC_X86_INS_FDIV = 146
'     UC_X86_INS_FIDIV = 147
'     UC_X86_INS_FDIVP = 148
'     UC_X86_INS_DPPD = 149
'     UC_X86_INS_DPPS = 150
'     UC_X86_INS_RET = 151
'     UC_X86_INS_ENCLS = 152
'     UC_X86_INS_ENCLU = 153
'     UC_X86_INS_ENTER = 154
'     UC_X86_INS_EXTRACTPS = 155
'     UC_X86_INS_EXTRQ = 156
'     UC_X86_INS_F2XM1 = 157
'     UC_X86_INS_LCALL = 158
'     UC_X86_INS_LJMP = 159
'     UC_X86_INS_FBLD = 160
'     UC_X86_INS_FBSTP = 161
'     UC_X86_INS_FCOMPP = 162
'     UC_X86_INS_FDECSTP = 163
'     UC_X86_INS_FEMMS = 164
'     UC_X86_INS_FFREE = 165
'     UC_X86_INS_FICOM = 166
'     UC_X86_INS_FICOMP = 167
'     UC_X86_INS_FINCSTP = 168
'     UC_X86_INS_FLDCW = 169
'     UC_X86_INS_FLDENV = 170
'     UC_X86_INS_FLDL2E = 171
'     UC_X86_INS_FLDL2T = 172
'     UC_X86_INS_FLDLG2 = 173
'     UC_X86_INS_FLDLN2 = 174
'     UC_X86_INS_FLDPI = 175
'     UC_X86_INS_FNCLEX = 176
'     UC_X86_INS_FNINIT = 177
'     UC_X86_INS_FNOP = 178
'     UC_X86_INS_FNSTCW = 179
'     UC_X86_INS_FNSTSW = 180
'     UC_X86_INS_FPATAN = 181
'     UC_X86_INS_FPREM = 182
'     UC_X86_INS_FPREM1 = 183
'     UC_X86_INS_FPTAN = 184
'     UC_X86_INS_FFREEP = 185
'     UC_X86_INS_FRNDINT = 186
'     UC_X86_INS_FRSTOR = 187
'     UC_X86_INS_FNSAVE = 188
'     UC_X86_INS_FSCALE = 189
'     UC_X86_INS_FSETPM = 190
'     UC_X86_INS_FSINCOS = 191
'     UC_X86_INS_FNSTENV = 192
'     UC_X86_INS_FXAM = 193
'     UC_X86_INS_FXRSTOR = 194
'     UC_X86_INS_FXRSTOR64 = 195
'     UC_X86_INS_FXSAVE = 196
'     UC_X86_INS_FXSAVE64 = 197
'     UC_X86_INS_FXTRACT = 198
'     UC_X86_INS_FYL2X = 199
'     UC_X86_INS_FYL2XP1 = 200
'     UC_X86_INS_MOVAPD = 201
'     UC_X86_INS_MOVAPS = 202
'     UC_X86_INS_ORPD = 203
'     UC_X86_INS_ORPS = 204
'     UC_X86_INS_VMOVAPD = 205
'     UC_X86_INS_VMOVAPS = 206
'     UC_X86_INS_XORPD = 207
'     UC_X86_INS_XORPS = 208
'     UC_X86_INS_GETSEC = 209
'     UC_X86_INS_HADDPD = 210
'     UC_X86_INS_HADDPS = 211
'     UC_X86_INS_HLT = 212
'     UC_X86_INS_HSUBPD = 213
'     UC_X86_INS_HSUBPS = 214
'     UC_X86_INS_IDIV = 215
'     UC_X86_INS_FILD = 216
'     UC_X86_INS_IMUL = 217
'     UC_X86_INS_IN = 218
'     UC_X86_INS_INC = 219
'     UC_X86_INS_INSB = 220
'     UC_X86_INS_INSERTPS = 221
'     UC_X86_INS_INSERTQ = 222
'     UC_X86_INS_INSD = 223
'     UC_X86_INS_INSW = 224
'     UC_X86_INS_INT = 225
'     UC_X86_INS_INT1 = 226
'     UC_X86_INS_INT3 = 227
'     UC_X86_INS_INTO = 228
'     UC_X86_INS_INVD = 229
'     UC_X86_INS_INVEPT = 230
'     UC_X86_INS_INVLPG = 231
'     UC_X86_INS_INVLPGA = 232
'     UC_X86_INS_INVPCID = 233
'     UC_X86_INS_INVVPID = 234
'     UC_X86_INS_IRET = 235
'     UC_X86_INS_IRETD = 236
'     UC_X86_INS_IRETQ = 237
'     UC_X86_INS_FISTTP = 238
'     UC_X86_INS_FIST = 239
'     UC_X86_INS_FISTP = 240
'     UC_X86_INS_UCOMISD = 241
'     UC_X86_INS_UCOMISS = 242
'     UC_X86_INS_VCOMISD = 243
'     UC_X86_INS_VCOMISS = 244
'     UC_X86_INS_VCVTSD2SS = 245
'     UC_X86_INS_VCVTSI2SD = 246
'     UC_X86_INS_VCVTSI2SS = 247
'     UC_X86_INS_VCVTSS2SD = 248
'     UC_X86_INS_VCVTTSD2SI = 249
'     UC_X86_INS_VCVTTSD2USI = 250
'     UC_X86_INS_VCVTTSS2SI = 251
'     UC_X86_INS_VCVTTSS2USI = 252
'     UC_X86_INS_VCVTUSI2SD = 253
'     UC_X86_INS_VCVTUSI2SS = 254
'     UC_X86_INS_VUCOMISD = 255
'     UC_X86_INS_VUCOMISS = 256
'     UC_X86_INS_JAE = 257
'     UC_X86_INS_JA = 258
'     UC_X86_INS_JBE = 259
'     UC_X86_INS_JB = 260
'     UC_X86_INS_JCXZ = 261
'     UC_X86_INS_JECXZ = 262
'     UC_X86_INS_JE = 263
'     UC_X86_INS_JGE = 264
'     UC_X86_INS_JG = 265
'     UC_X86_INS_JLE = 266
'     UC_X86_INS_JL = 267
'     UC_X86_INS_JMP = 268
'     UC_X86_INS_JNE = 269
'     UC_X86_INS_JNO = 270
'     UC_X86_INS_JNP = 271
'     UC_X86_INS_JNS = 272
'     UC_X86_INS_JO = 273
'     UC_X86_INS_JP = 274
'     UC_X86_INS_JRCXZ = 275
'     UC_X86_INS_JS = 276
'     UC_X86_INS_KANDB = 277
'     UC_X86_INS_KANDD = 278
'     UC_X86_INS_KANDNB = 279
'     UC_X86_INS_KANDND = 280
'     UC_X86_INS_KANDNQ = 281
'     UC_X86_INS_KANDNW = 282
'     UC_X86_INS_KANDQ = 283
'     UC_X86_INS_KANDW = 284
'     UC_X86_INS_KMOVB = 285
'     UC_X86_INS_KMOVD = 286
'     UC_X86_INS_KMOVQ = 287
'     UC_X86_INS_KMOVW = 288
'     UC_X86_INS_KNOTB = 289
'     UC_X86_INS_KNOTD = 290
'     UC_X86_INS_KNOTQ = 291
'     UC_X86_INS_KNOTW = 292
'     UC_X86_INS_KORB = 293
'     UC_X86_INS_KORD = 294
'     UC_X86_INS_KORQ = 295
'     UC_X86_INS_KORTESTB = 296
'     UC_X86_INS_KORTESTD = 297
'     UC_X86_INS_KORTESTQ = 298
'     UC_X86_INS_KORTESTW = 299
'     UC_X86_INS_KORW = 300
'     UC_X86_INS_KSHIFTLB = 301
'     UC_X86_INS_KSHIFTLD = 302
'     UC_X86_INS_KSHIFTLQ = 303
'     UC_X86_INS_KSHIFTLW = 304
'     UC_X86_INS_KSHIFTRB = 305
'     UC_X86_INS_KSHIFTRD = 306
'     UC_X86_INS_KSHIFTRQ = 307
'     UC_X86_INS_KSHIFTRW = 308
'     UC_X86_INS_KUNPCKBW = 309
'     UC_X86_INS_KXNORB = 310
'     UC_X86_INS_KXNORD = 311
'     UC_X86_INS_KXNORQ = 312
'     UC_X86_INS_KXNORW = 313
'     UC_X86_INS_KXORB = 314
'     UC_X86_INS_KXORD = 315
'     UC_X86_INS_KXORQ = 316
'     UC_X86_INS_KXORW = 317
'     UC_X86_INS_LAHF = 318
'     UC_X86_INS_LAR = 319
'     UC_X86_INS_LDDQU = 320
'     UC_X86_INS_LDMXCSR = 321
'     UC_X86_INS_LDS = 322
'     UC_X86_INS_FLDZ = 323
'     UC_X86_INS_FLD1 = 324
'     UC_X86_INS_FLD = 325
'     UC_X86_INS_LEA = 326
'     UC_X86_INS_LEAVE = 327
'     UC_X86_INS_LES = 328
'     UC_X86_INS_LFENCE = 329
'     UC_X86_INS_LFS = 330
'     UC_X86_INS_LGDT = 331
'     UC_X86_INS_LGS = 332
'     UC_X86_INS_LIDT = 333
'     UC_X86_INS_LLDT = 334
'     UC_X86_INS_LMSW = 335
'     UC_X86_INS_OR = 336
'     UC_X86_INS_SUB = 337
'     UC_X86_INS_XOR = 338
'     UC_X86_INS_LODSB = 339
'     UC_X86_INS_LODSD = 340
'     UC_X86_INS_LODSQ = 341
'     UC_X86_INS_LODSW = 342
'     UC_X86_INS_LOOP = 343
'     UC_X86_INS_LOOPE = 344
'     UC_X86_INS_LOOPNE = 345
'     UC_X86_INS_RETF = 346
'     UC_X86_INS_RETFQ = 347
'     UC_X86_INS_LSL = 348
'     UC_X86_INS_LSS = 349
'     UC_X86_INS_LTR = 350
'     UC_X86_INS_XADD = 351
'     UC_X86_INS_LZCNT = 352
'     UC_X86_INS_MASKMOVDQU = 353
'     UC_X86_INS_MAXPD = 354
'     UC_X86_INS_MAXPS = 355
'     UC_X86_INS_MAXSD = 356
'     UC_X86_INS_MAXSS = 357
'     UC_X86_INS_MFENCE = 358
'     UC_X86_INS_MINPD = 359
'     UC_X86_INS_MINPS = 360
'     UC_X86_INS_MINSD = 361
'     UC_X86_INS_MINSS = 362
'     UC_X86_INS_CVTPD2PI = 363
'     UC_X86_INS_CVTPI2PD = 364
'     UC_X86_INS_CVTPI2PS = 365
'     UC_X86_INS_CVTPS2PI = 366
'     UC_X86_INS_CVTTPD2PI = 367
'     UC_X86_INS_CVTTPS2PI = 368
'     UC_X86_INS_EMMS = 369
'     UC_X86_INS_MASKMOVQ = 370
'     UC_X86_INS_MOVD = 371
'     UC_X86_INS_MOVDQ2Q = 372
'     UC_X86_INS_MOVNTQ = 373
'     UC_X86_INS_MOVQ2DQ = 374
'     UC_X86_INS_MOVQ = 375
'     UC_X86_INS_PABSB = 376
'     UC_X86_INS_PABSD = 377
'     UC_X86_INS_PABSW = 378
'     UC_X86_INS_PACKSSDW = 379
'     UC_X86_INS_PACKSSWB = 380
'     UC_X86_INS_PACKUSWB = 381
'     UC_X86_INS_PADDB = 382
'     UC_X86_INS_PADDD = 383
'     UC_X86_INS_PADDQ = 384
'     UC_X86_INS_PADDSB = 385
'     UC_X86_INS_PADDSW = 386
'     UC_X86_INS_PADDUSB = 387
'     UC_X86_INS_PADDUSW = 388
'     UC_X86_INS_PADDW = 389
'     UC_X86_INS_PALIGNR = 390
'     UC_X86_INS_PANDN = 391
'     UC_X86_INS_PAND = 392
'     UC_X86_INS_PAVGB = 393
'     UC_X86_INS_PAVGW = 394
'     UC_X86_INS_PCMPEQB = 395
'     UC_X86_INS_PCMPEQD = 396
'     UC_X86_INS_PCMPEQW = 397
'     UC_X86_INS_PCMPGTB = 398
'     UC_X86_INS_PCMPGTD = 399
'     UC_X86_INS_PCMPGTW = 400
'     UC_X86_INS_PEXTRW = 401
'     UC_X86_INS_PHADDSW = 402
'     UC_X86_INS_PHADDW = 403
'     UC_X86_INS_PHADDD = 404
'     UC_X86_INS_PHSUBD = 405
'     UC_X86_INS_PHSUBSW = 406
'     UC_X86_INS_PHSUBW = 407
'     UC_X86_INS_PINSRW = 408
'     UC_X86_INS_PMADDUBSW = 409
'     UC_X86_INS_PMADDWD = 410
'     UC_X86_INS_PMAXSW = 411
'     UC_X86_INS_PMAXUB = 412
'     UC_X86_INS_PMINSW = 413
'     UC_X86_INS_PMINUB = 414
'     UC_X86_INS_PMOVMSKB = 415
'     UC_X86_INS_PMULHRSW = 416
'     UC_X86_INS_PMULHUW = 417
'     UC_X86_INS_PMULHW = 418
'     UC_X86_INS_PMULLW = 419
'     UC_X86_INS_PMULUDQ = 420
'     UC_X86_INS_POR = 421
'     UC_X86_INS_PSADBW = 422
'     UC_X86_INS_PSHUFB = 423
'     UC_X86_INS_PSHUFW = 424
'     UC_X86_INS_PSIGNB = 425
'     UC_X86_INS_PSIGND = 426
'     UC_X86_INS_PSIGNW = 427
'     UC_X86_INS_PSLLD = 428
'     UC_X86_INS_PSLLQ = 429
'     UC_X86_INS_PSLLW = 430
'     UC_X86_INS_PSRAD = 431
'     UC_X86_INS_PSRAW = 432
'     UC_X86_INS_PSRLD = 433
'     UC_X86_INS_PSRLQ = 434
'     UC_X86_INS_PSRLW = 435
'     UC_X86_INS_PSUBB = 436
'     UC_X86_INS_PSUBD = 437
'     UC_X86_INS_PSUBQ = 438
'     UC_X86_INS_PSUBSB = 439
'     UC_X86_INS_PSUBSW = 440
'     UC_X86_INS_PSUBUSB = 441
'     UC_X86_INS_PSUBUSW = 442
'     UC_X86_INS_PSUBW = 443
'     UC_X86_INS_PUNPCKHBW = 444
'     UC_X86_INS_PUNPCKHDQ = 445
'     UC_X86_INS_PUNPCKHWD = 446
'     UC_X86_INS_PUNPCKLBW = 447
'     UC_X86_INS_PUNPCKLDQ = 448
'     UC_X86_INS_PUNPCKLWD = 449
'     UC_X86_INS_PXOR = 450
'     UC_X86_INS_MONITOR = 451
'     UC_X86_INS_MONTMUL = 452
'     UC_X86_INS_MOV = 453
'     UC_X86_INS_MOVABS = 454
'     UC_X86_INS_MOVBE = 455
'     UC_X86_INS_MOVDDUP = 456
'     UC_X86_INS_MOVDQA = 457
'     UC_X86_INS_MOVDQU = 458
'     UC_X86_INS_MOVHLPS = 459
'     UC_X86_INS_MOVHPD = 460
'     UC_X86_INS_MOVHPS = 461
'     UC_X86_INS_MOVLHPS = 462
'     UC_X86_INS_MOVLPD = 463
'     UC_X86_INS_MOVLPS = 464
'     UC_X86_INS_MOVMSKPD = 465
'     UC_X86_INS_MOVMSKPS = 466
'     UC_X86_INS_MOVNTDQA = 467
'     UC_X86_INS_MOVNTDQ = 468
'     UC_X86_INS_MOVNTI = 469
'     UC_X86_INS_MOVNTPD = 470
'     UC_X86_INS_MOVNTPS = 471
'     UC_X86_INS_MOVNTSD = 472
'     UC_X86_INS_MOVNTSS = 473
'     UC_X86_INS_MOVSB = 474
'     UC_X86_INS_MOVSD = 475
'     UC_X86_INS_MOVSHDUP = 476
'     UC_X86_INS_MOVSLDUP = 477
'     UC_X86_INS_MOVSQ = 478
'     UC_X86_INS_MOVSS = 479
'     UC_X86_INS_MOVSW = 480
'     UC_X86_INS_MOVSX = 481
'     UC_X86_INS_MOVSXD = 482
'     UC_X86_INS_MOVUPD = 483
'     UC_X86_INS_MOVUPS = 484
'     UC_X86_INS_MOVZX = 485
'     UC_X86_INS_MPSADBW = 486
'     UC_X86_INS_MUL = 487
'     UC_X86_INS_MULPD = 488
'     UC_X86_INS_MULPS = 489
'     UC_X86_INS_MULSD = 490
'     UC_X86_INS_MULSS = 491
'     UC_X86_INS_MULX = 492
'     UC_X86_INS_FMUL = 493
'     UC_X86_INS_FIMUL = 494
'     UC_X86_INS_FMULP = 495
'     UC_X86_INS_MWAIT = 496
'     UC_X86_INS_NEG = 497
'     UC_X86_INS_NOP = 498
'     UC_X86_INS_NOT = 499
'     UC_X86_INS_OUT = 500
'     UC_X86_INS_OUTSB = 501
'     UC_X86_INS_OUTSD = 502
'     UC_X86_INS_OUTSW = 503
'     UC_X86_INS_PACKUSDW = 504
'     UC_X86_INS_PAUSE = 505
'     UC_X86_INS_PAVGUSB = 506
'     UC_X86_INS_PBLENDVB = 507
'     UC_X86_INS_PBLENDW = 508
'     UC_X86_INS_PCLMULQDQ = 509
'     UC_X86_INS_PCMPEQQ = 510
'     UC_X86_INS_PCMPESTRI = 511
'     UC_X86_INS_PCMPESTRM = 512
'     UC_X86_INS_PCMPGTQ = 513
'     UC_X86_INS_PCMPISTRI = 514
'     UC_X86_INS_PCMPISTRM = 515
'     UC_X86_INS_PCOMMIT = 516
'     UC_X86_INS_PDEP = 517
'     UC_X86_INS_PEXT = 518
'     UC_X86_INS_PEXTRB = 519
'     UC_X86_INS_PEXTRD = 520
'     UC_X86_INS_PEXTRQ = 521
'     UC_X86_INS_PF2ID = 522
'     UC_X86_INS_PF2IW = 523
'     UC_X86_INS_PFACC = 524
'     UC_X86_INS_PFADD = 525
'     UC_X86_INS_PFCMPEQ = 526
'     UC_X86_INS_PFCMPGE = 527
'     UC_X86_INS_PFCMPGT = 528
'     UC_X86_INS_PFMAX = 529
'     UC_X86_INS_PFMIN = 530
'     UC_X86_INS_PFMUL = 531
'     UC_X86_INS_PFNACC = 532
'     UC_X86_INS_PFPNACC = 533
'     UC_X86_INS_PFRCPIT1 = 534
'     UC_X86_INS_PFRCPIT2 = 535
'     UC_X86_INS_PFRCP = 536
'     UC_X86_INS_PFRSQIT1 = 537
'     UC_X86_INS_PFRSQRT = 538
'     UC_X86_INS_PFSUBR = 539
'     UC_X86_INS_PFSUB = 540
'     UC_X86_INS_PHMINPOSUW = 541
'     UC_X86_INS_PI2FD = 542
'     UC_X86_INS_PI2FW = 543
'     UC_X86_INS_PINSRB = 544
'     UC_X86_INS_PINSRD = 545
'     UC_X86_INS_PINSRQ = 546
'     UC_X86_INS_PMAXSB = 547
'     UC_X86_INS_PMAXSD = 548
'     UC_X86_INS_PMAXUD = 549
'     UC_X86_INS_PMAXUW = 550
'     UC_X86_INS_PMINSB = 551
'     UC_X86_INS_PMINSD = 552
'     UC_X86_INS_PMINUD = 553
'     UC_X86_INS_PMINUW = 554
'     UC_X86_INS_PMOVSXBD = 555
'     UC_X86_INS_PMOVSXBQ = 556
'     UC_X86_INS_PMOVSXBW = 557
'     UC_X86_INS_PMOVSXDQ = 558
'     UC_X86_INS_PMOVSXWD = 559
'     UC_X86_INS_PMOVSXWQ = 560
'     UC_X86_INS_PMOVZXBD = 561
'     UC_X86_INS_PMOVZXBQ = 562
'     UC_X86_INS_PMOVZXBW = 563
'     UC_X86_INS_PMOVZXDQ = 564
'     UC_X86_INS_PMOVZXWD = 565
'     UC_X86_INS_PMOVZXWQ = 566
'     UC_X86_INS_PMULDQ = 567
'     UC_X86_INS_PMULHRW = 568
'     UC_X86_INS_PMULLD = 569
'     UC_X86_INS_POP = 570
'     UC_X86_INS_POPAW = 571
'     UC_X86_INS_POPAL = 572
'     UC_X86_INS_POPCNT = 573
'     UC_X86_INS_POPF = 574
'     UC_X86_INS_POPFD = 575
'     UC_X86_INS_POPFQ = 576
'     UC_X86_INS_PREFETCH = 577
'     UC_X86_INS_PREFETCHNTA = 578
'     UC_X86_INS_PREFETCHT0 = 579
'     UC_X86_INS_PREFETCHT1 = 580
'     UC_X86_INS_PREFETCHT2 = 581
'     UC_X86_INS_PREFETCHW = 582
'     UC_X86_INS_PSHUFD = 583
'     UC_X86_INS_PSHUFHW = 584
'     UC_X86_INS_PSHUFLW = 585
'     UC_X86_INS_PSLLDQ = 586
'     UC_X86_INS_PSRLDQ = 587
'     UC_X86_INS_PSWAPD = 588
'     UC_X86_INS_PTEST = 589
'     UC_X86_INS_PUNPCKHQDQ = 590
'     UC_X86_INS_PUNPCKLQDQ = 591
'     UC_X86_INS_PUSH = 592
'     UC_X86_INS_PUSHAW = 593
'     UC_X86_INS_PUSHAL = 594
'     UC_X86_INS_PUSHF = 595
'     UC_X86_INS_PUSHFD = 596
'     UC_X86_INS_PUSHFQ = 597
'     UC_X86_INS_RCL = 598
'     UC_X86_INS_RCPPS = 599
'     UC_X86_INS_RCPSS = 600
'     UC_X86_INS_RCR = 601
'     UC_X86_INS_RDFSBASE = 602
'     UC_X86_INS_RDGSBASE = 603
'     UC_X86_INS_RDMSR = 604
'     UC_X86_INS_RDPMC = 605
'     UC_X86_INS_RDRAND = 606
'     UC_X86_INS_RDSEED = 607
'     UC_X86_INS_RDTSC = 608
'     UC_X86_INS_RDTSCP = 609
'     UC_X86_INS_ROL = 610
'     UC_X86_INS_ROR = 611
'     UC_X86_INS_RORX = 612
'     UC_X86_INS_ROUNDPD = 613
'     UC_X86_INS_ROUNDPS = 614
'     UC_X86_INS_ROUNDSD = 615
'     UC_X86_INS_ROUNDSS = 616
'     UC_X86_INS_RSM = 617
'     UC_X86_INS_RSQRTPS = 618
'     UC_X86_INS_RSQRTSS = 619
'     UC_X86_INS_SAHF = 620
'     UC_X86_INS_SAL = 621
'     UC_X86_INS_SALC = 622
'     UC_X86_INS_SAR = 623
'     UC_X86_INS_SARX = 624
'     UC_X86_INS_SBB = 625
'     UC_X86_INS_SCASB = 626
'     UC_X86_INS_SCASD = 627
'     UC_X86_INS_SCASQ = 628
'     UC_X86_INS_SCASW = 629
'     UC_X86_INS_SETAE = 630
'     UC_X86_INS_SETA = 631
'     UC_X86_INS_SETBE = 632
'     UC_X86_INS_SETB = 633
'     UC_X86_INS_SETE = 634
'     UC_X86_INS_SETGE = 635
'     UC_X86_INS_SETG = 636
'     UC_X86_INS_SETLE = 637
'     UC_X86_INS_SETL = 638
'     UC_X86_INS_SETNE = 639
'     UC_X86_INS_SETNO = 640
'     UC_X86_INS_SETNP = 641
'     UC_X86_INS_SETNS = 642
'     UC_X86_INS_SETO = 643
'     UC_X86_INS_SETP = 644
'     UC_X86_INS_SETS = 645
'     UC_X86_INS_SFENCE = 646
'     UC_X86_INS_SGDT = 647
'     UC_X86_INS_SHA1MSG1 = 648
'     UC_X86_INS_SHA1MSG2 = 649
'     UC_X86_INS_SHA1NEXTE = 650
'     UC_X86_INS_SHA1RNDS4 = 651
'     UC_X86_INS_SHA256MSG1 = 652
'     UC_X86_INS_SHA256MSG2 = 653
'     UC_X86_INS_SHA256RNDS2 = 654
'     UC_X86_INS_SHL = 655
'     UC_X86_INS_SHLD = 656
'     UC_X86_INS_SHLX = 657
'     UC_X86_INS_SHR = 658
'     UC_X86_INS_SHRD = 659
'     UC_X86_INS_SHRX = 660
'     UC_X86_INS_SHUFPD = 661
'     UC_X86_INS_SHUFPS = 662
'     UC_X86_INS_SIDT = 663
'     UC_X86_INS_FSIN = 664
'     UC_X86_INS_SKINIT = 665
'     UC_X86_INS_SLDT = 666
'     UC_X86_INS_SMSW = 667
'     UC_X86_INS_SQRTPD = 668
'     UC_X86_INS_SQRTPS = 669
'     UC_X86_INS_SQRTSD = 670
'     UC_X86_INS_SQRTSS = 671
'     UC_X86_INS_FSQRT = 672
'     UC_X86_INS_STAC = 673
'     UC_X86_INS_STC = 674
'     UC_X86_INS_STD = 675
'     UC_X86_INS_STGI = 676
'     UC_X86_INS_STI = 677
'     UC_X86_INS_STMXCSR = 678
'     UC_X86_INS_STOSB = 679
'     UC_X86_INS_STOSD = 680
'     UC_X86_INS_STOSQ = 681
'     UC_X86_INS_STOSW = 682
'     UC_X86_INS_STR = 683
'     UC_X86_INS_FST = 684
'     UC_X86_INS_FSTP = 685
'     UC_X86_INS_FSTPNCE = 686
'     UC_X86_INS_FXCH = 687
'     UC_X86_INS_SUBPD = 688
'     UC_X86_INS_SUBPS = 689
'     UC_X86_INS_FSUBR = 690
'     UC_X86_INS_FISUBR = 691
'     UC_X86_INS_FSUBRP = 692
'     UC_X86_INS_SUBSD = 693
'     UC_X86_INS_SUBSS = 694
'     UC_X86_INS_FSUB = 695
'     UC_X86_INS_FISUB = 696
'     UC_X86_INS_FSUBP = 697
'     UC_X86_INS_SWAPGS = 698
'     UC_X86_INS_SYSCALL = 699
'     UC_X86_INS_SYSENTER = 700
'     UC_X86_INS_SYSEXIT = 701
'     UC_X86_INS_SYSRET = 702
'     UC_X86_INS_T1MSKC = 703
'     UC_X86_INS_TEST = 704
'     UC_X86_INS_UD2 = 705
'     UC_X86_INS_FTST = 706
'     UC_X86_INS_TZCNT = 707
'     UC_X86_INS_TZMSK = 708
'     UC_X86_INS_FUCOMPI = 709
'     UC_X86_INS_FUCOMI = 710
'     UC_X86_INS_FUCOMPP = 711
'     UC_X86_INS_FUCOMP = 712
'     UC_X86_INS_FUCOM = 713
'     UC_X86_INS_UD2B = 714
'     UC_X86_INS_UNPCKHPD = 715
'     UC_X86_INS_UNPCKHPS = 716
'     UC_X86_INS_UNPCKLPD = 717
'     UC_X86_INS_UNPCKLPS = 718
'     UC_X86_INS_VADDPD = 719
'     UC_X86_INS_VADDPS = 720
'     UC_X86_INS_VADDSD = 721
'     UC_X86_INS_VADDSS = 722
'     UC_X86_INS_VADDSUBPD = 723
'     UC_X86_INS_VADDSUBPS = 724
'     UC_X86_INS_VAESDECLAST = 725
'     UC_X86_INS_VAESDEC = 726
'     UC_X86_INS_VAESENCLAST = 727
'     UC_X86_INS_VAESENC = 728
'     UC_X86_INS_VAESIMC = 729
'     UC_X86_INS_VAESKEYGENASSIST = 730
'     UC_X86_INS_VALIGND = 731
'     UC_X86_INS_VALIGNQ = 732
'     UC_X86_INS_VANDNPD = 733
'     UC_X86_INS_VANDNPS = 734
'     UC_X86_INS_VANDPD = 735
'     UC_X86_INS_VANDPS = 736
'     UC_X86_INS_VBLENDMPD = 737
'     UC_X86_INS_VBLENDMPS = 738
'     UC_X86_INS_VBLENDPD = 739
'     UC_X86_INS_VBLENDPS = 740
'     UC_X86_INS_VBLENDVPD = 741
'     UC_X86_INS_VBLENDVPS = 742
'     UC_X86_INS_VBROADCASTF128 = 743
'     UC_X86_INS_VBROADCASTI32X4 = 744
'     UC_X86_INS_VBROADCASTI64X4 = 745
'     UC_X86_INS_VBROADCASTSD = 746
'     UC_X86_INS_VBROADCASTSS = 747
'     UC_X86_INS_VCMPPD = 748
'     UC_X86_INS_VCMPPS = 749
'     UC_X86_INS_VCMPSD = 750
'     UC_X86_INS_VCMPSS = 751
'     UC_X86_INS_VCOMPRESSPD = 752
'     UC_X86_INS_VCOMPRESSPS = 753
'     UC_X86_INS_VCVTDQ2PD = 754
'     UC_X86_INS_VCVTDQ2PS = 755
'     UC_X86_INS_VCVTPD2DQX = 756
'     UC_X86_INS_VCVTPD2DQ = 757
'     UC_X86_INS_VCVTPD2PSX = 758
'     UC_X86_INS_VCVTPD2PS = 759
'     UC_X86_INS_VCVTPD2UDQ = 760
'     UC_X86_INS_VCVTPH2PS = 761
'     UC_X86_INS_VCVTPS2DQ = 762
'     UC_X86_INS_VCVTPS2PD = 763
'     UC_X86_INS_VCVTPS2PH = 764
'     UC_X86_INS_VCVTPS2UDQ = 765
'     UC_X86_INS_VCVTSD2SI = 766
'     UC_X86_INS_VCVTSD2USI = 767
'     UC_X86_INS_VCVTSS2SI = 768
'     UC_X86_INS_VCVTSS2USI = 769
'     UC_X86_INS_VCVTTPD2DQX = 770
'     UC_X86_INS_VCVTTPD2DQ = 771
'     UC_X86_INS_VCVTTPD2UDQ = 772
'     UC_X86_INS_VCVTTPS2DQ = 773
'     UC_X86_INS_VCVTTPS2UDQ = 774
'     UC_X86_INS_VCVTUDQ2PD = 775
'     UC_X86_INS_VCVTUDQ2PS = 776
'     UC_X86_INS_VDIVPD = 777
'     UC_X86_INS_VDIVPS = 778
'     UC_X86_INS_VDIVSD = 779
'     UC_X86_INS_VDIVSS = 780
'     UC_X86_INS_VDPPD = 781
'     UC_X86_INS_VDPPS = 782
'     UC_X86_INS_VERR = 783
'     UC_X86_INS_VERW = 784
'     UC_X86_INS_VEXP2PD = 785
'     UC_X86_INS_VEXP2PS = 786
'     UC_X86_INS_VEXPANDPD = 787
'     UC_X86_INS_VEXPANDPS = 788
'     UC_X86_INS_VEXTRACTF128 = 789
'     UC_X86_INS_VEXTRACTF32X4 = 790
'     UC_X86_INS_VEXTRACTF64X4 = 791
'     UC_X86_INS_VEXTRACTI128 = 792
'     UC_X86_INS_VEXTRACTI32X4 = 793
'     UC_X86_INS_VEXTRACTI64X4 = 794
'     UC_X86_INS_VEXTRACTPS = 795
'     UC_X86_INS_VFMADD132PD = 796
'     UC_X86_INS_VFMADD132PS = 797
'     UC_X86_INS_VFMADDPD = 798
'     UC_X86_INS_VFMADD213PD = 799
'     UC_X86_INS_VFMADD231PD = 800
'     UC_X86_INS_VFMADDPS = 801
'     UC_X86_INS_VFMADD213PS = 802
'     UC_X86_INS_VFMADD231PS = 803
'     UC_X86_INS_VFMADDSD = 804
'     UC_X86_INS_VFMADD213SD = 805
'     UC_X86_INS_VFMADD132SD = 806
'     UC_X86_INS_VFMADD231SD = 807
'     UC_X86_INS_VFMADDSS = 808
'     UC_X86_INS_VFMADD213SS = 809
'     UC_X86_INS_VFMADD132SS = 810
'     UC_X86_INS_VFMADD231SS = 811
'     UC_X86_INS_VFMADDSUB132PD = 812
'     UC_X86_INS_VFMADDSUB132PS = 813
'     UC_X86_INS_VFMADDSUBPD = 814
'     UC_X86_INS_VFMADDSUB213PD = 815
'     UC_X86_INS_VFMADDSUB231PD = 816
'     UC_X86_INS_VFMADDSUBPS = 817
'     UC_X86_INS_VFMADDSUB213PS = 818
'     UC_X86_INS_VFMADDSUB231PS = 819
'     UC_X86_INS_VFMSUB132PD = 820
'     UC_X86_INS_VFMSUB132PS = 821
'     UC_X86_INS_VFMSUBADD132PD = 822
'     UC_X86_INS_VFMSUBADD132PS = 823
'     UC_X86_INS_VFMSUBADDPD = 824
'     UC_X86_INS_VFMSUBADD213PD = 825
'     UC_X86_INS_VFMSUBADD231PD = 826
'     UC_X86_INS_VFMSUBADDPS = 827
'     UC_X86_INS_VFMSUBADD213PS = 828
'     UC_X86_INS_VFMSUBADD231PS = 829
'     UC_X86_INS_VFMSUBPD = 830
'     UC_X86_INS_VFMSUB213PD = 831
'     UC_X86_INS_VFMSUB231PD = 832
'     UC_X86_INS_VFMSUBPS = 833
'     UC_X86_INS_VFMSUB213PS = 834
'     UC_X86_INS_VFMSUB231PS = 835
'     UC_X86_INS_VFMSUBSD = 836
'     UC_X86_INS_VFMSUB213SD = 837
'     UC_X86_INS_VFMSUB132SD = 838
'     UC_X86_INS_VFMSUB231SD = 839
'     UC_X86_INS_VFMSUBSS = 840
'     UC_X86_INS_VFMSUB213SS = 841
'     UC_X86_INS_VFMSUB132SS = 842
'     UC_X86_INS_VFMSUB231SS = 843
'     UC_X86_INS_VFNMADD132PD = 844
'     UC_X86_INS_VFNMADD132PS = 845
'     UC_X86_INS_VFNMADDPD = 846
'     UC_X86_INS_VFNMADD213PD = 847
'     UC_X86_INS_VFNMADD231PD = 848
'     UC_X86_INS_VFNMADDPS = 849
'     UC_X86_INS_VFNMADD213PS = 850
'     UC_X86_INS_VFNMADD231PS = 851
'     UC_X86_INS_VFNMADDSD = 852
'     UC_X86_INS_VFNMADD213SD = 853
'     UC_X86_INS_VFNMADD132SD = 854
'     UC_X86_INS_VFNMADD231SD = 855
'     UC_X86_INS_VFNMADDSS = 856
'     UC_X86_INS_VFNMADD213SS = 857
'     UC_X86_INS_VFNMADD132SS = 858
'     UC_X86_INS_VFNMADD231SS = 859
'     UC_X86_INS_VFNMSUB132PD = 860
'     UC_X86_INS_VFNMSUB132PS = 861
'     UC_X86_INS_VFNMSUBPD = 862
'     UC_X86_INS_VFNMSUB213PD = 863
'     UC_X86_INS_VFNMSUB231PD = 864
'     UC_X86_INS_VFNMSUBPS = 865
'     UC_X86_INS_VFNMSUB213PS = 866
'     UC_X86_INS_VFNMSUB231PS = 867
'     UC_X86_INS_VFNMSUBSD = 868
'     UC_X86_INS_VFNMSUB213SD = 869
'     UC_X86_INS_VFNMSUB132SD = 870
'     UC_X86_INS_VFNMSUB231SD = 871
'     UC_X86_INS_VFNMSUBSS = 872
'     UC_X86_INS_VFNMSUB213SS = 873
'     UC_X86_INS_VFNMSUB132SS = 874
'     UC_X86_INS_VFNMSUB231SS = 875
'     UC_X86_INS_VFRCZPD = 876
'     UC_X86_INS_VFRCZPS = 877
'     UC_X86_INS_VFRCZSD = 878
'     UC_X86_INS_VFRCZSS = 879
'     UC_X86_INS_VORPD = 880
'     UC_X86_INS_VORPS = 881
'     UC_X86_INS_VXORPD = 882
'     UC_X86_INS_VXORPS = 883
'     UC_X86_INS_VGATHERDPD = 884
'     UC_X86_INS_VGATHERDPS = 885
'     UC_X86_INS_VGATHERPF0DPD = 886
'     UC_X86_INS_VGATHERPF0DPS = 887
'     UC_X86_INS_VGATHERPF0QPD = 888
'     UC_X86_INS_VGATHERPF0QPS = 889
'     UC_X86_INS_VGATHERPF1DPD = 890
'     UC_X86_INS_VGATHERPF1DPS = 891
'     UC_X86_INS_VGATHERPF1QPD = 892
'     UC_X86_INS_VGATHERPF1QPS = 893
'     UC_X86_INS_VGATHERQPD = 894
'     UC_X86_INS_VGATHERQPS = 895
'     UC_X86_INS_VHADDPD = 896
'     UC_X86_INS_VHADDPS = 897
'     UC_X86_INS_VHSUBPD = 898
'     UC_X86_INS_VHSUBPS = 899
'     UC_X86_INS_VINSERTF128 = 900
'     UC_X86_INS_VINSERTF32X4 = 901
'     UC_X86_INS_VINSERTF32X8 = 902
'     UC_X86_INS_VINSERTF64X2 = 903
'     UC_X86_INS_VINSERTF64X4 = 904
'     UC_X86_INS_VINSERTI128 = 905
'     UC_X86_INS_VINSERTI32X4 = 906
'     UC_X86_INS_VINSERTI32X8 = 907
'     UC_X86_INS_VINSERTI64X2 = 908
'     UC_X86_INS_VINSERTI64X4 = 909
'     UC_X86_INS_VINSERTPS = 910
'     UC_X86_INS_VLDDQU = 911
'     UC_X86_INS_VLDMXCSR = 912
'     UC_X86_INS_VMASKMOVDQU = 913
'     UC_X86_INS_VMASKMOVPD = 914
'     UC_X86_INS_VMASKMOVPS = 915
'     UC_X86_INS_VMAXPD = 916
'     UC_X86_INS_VMAXPS = 917
'     UC_X86_INS_VMAXSD = 918
'     UC_X86_INS_VMAXSS = 919
'     UC_X86_INS_VMCALL = 920
'     UC_X86_INS_VMCLEAR = 921
'     UC_X86_INS_VMFUNC = 922
'     UC_X86_INS_VMINPD = 923
'     UC_X86_INS_VMINPS = 924
'     UC_X86_INS_VMINSD = 925
'     UC_X86_INS_VMINSS = 926
'     UC_X86_INS_VMLAUNCH = 927
'     UC_X86_INS_VMLOAD = 928
'     UC_X86_INS_VMMCALL = 929
'     UC_X86_INS_VMOVQ = 930
'     UC_X86_INS_VMOVDDUP = 931
'     UC_X86_INS_VMOVD = 932
'     UC_X86_INS_VMOVDQA32 = 933
'     UC_X86_INS_VMOVDQA64 = 934
'     UC_X86_INS_VMOVDQA = 935
'     UC_X86_INS_VMOVDQU16 = 936
'     UC_X86_INS_VMOVDQU32 = 937
'     UC_X86_INS_VMOVDQU64 = 938
'     UC_X86_INS_VMOVDQU8 = 939
'     UC_X86_INS_VMOVDQU = 940
'     UC_X86_INS_VMOVHLPS = 941
'     UC_X86_INS_VMOVHPD = 942
'     UC_X86_INS_VMOVHPS = 943
'     UC_X86_INS_VMOVLHPS = 944
'     UC_X86_INS_VMOVLPD = 945
'     UC_X86_INS_VMOVLPS = 946
'     UC_X86_INS_VMOVMSKPD = 947
'     UC_X86_INS_VMOVMSKPS = 948
'     UC_X86_INS_VMOVNTDQA = 949
'     UC_X86_INS_VMOVNTDQ = 950
'     UC_X86_INS_VMOVNTPD = 951
'     UC_X86_INS_VMOVNTPS = 952
'     UC_X86_INS_VMOVSD = 953
'     UC_X86_INS_VMOVSHDUP = 954
'     UC_X86_INS_VMOVSLDUP = 955
'     UC_X86_INS_VMOVSS = 956
'     UC_X86_INS_VMOVUPD = 957
'     UC_X86_INS_VMOVUPS = 958
'     UC_X86_INS_VMPSADBW = 959
'     UC_X86_INS_VMPTRLD = 960
'     UC_X86_INS_VMPTRST = 961
'     UC_X86_INS_VMREAD = 962
'     UC_X86_INS_VMRESUME = 963
'     UC_X86_INS_VMRUN = 964
'     UC_X86_INS_VMSAVE = 965
'     UC_X86_INS_VMULPD = 966
'     UC_X86_INS_VMULPS = 967
'     UC_X86_INS_VMULSD = 968
'     UC_X86_INS_VMULSS = 969
'     UC_X86_INS_VMWRITE = 970
'     UC_X86_INS_VMXOFF = 971
'     UC_X86_INS_VMXON = 972
'     UC_X86_INS_VPABSB = 973
'     UC_X86_INS_VPABSD = 974
'     UC_X86_INS_VPABSQ = 975
'     UC_X86_INS_VPABSW = 976
'     UC_X86_INS_VPACKSSDW = 977
'     UC_X86_INS_VPACKSSWB = 978
'     UC_X86_INS_VPACKUSDW = 979
'     UC_X86_INS_VPACKUSWB = 980
'     UC_X86_INS_VPADDB = 981
'     UC_X86_INS_VPADDD = 982
'     UC_X86_INS_VPADDQ = 983
'     UC_X86_INS_VPADDSB = 984
'     UC_X86_INS_VPADDSW = 985
'     UC_X86_INS_VPADDUSB = 986
'     UC_X86_INS_VPADDUSW = 987
'     UC_X86_INS_VPADDW = 988
'     UC_X86_INS_VPALIGNR = 989
'     UC_X86_INS_VPANDD = 990
'     UC_X86_INS_VPANDND = 991
'     UC_X86_INS_VPANDNQ = 992
'     UC_X86_INS_VPANDN = 993
'     UC_X86_INS_VPANDQ = 994
'     UC_X86_INS_VPAND = 995
'     UC_X86_INS_VPAVGB = 996
'     UC_X86_INS_VPAVGW = 997
'     UC_X86_INS_VPBLENDD = 998
'     UC_X86_INS_VPBLENDMB = 999
'     UC_X86_INS_VPBLENDMD = 1000
'     UC_X86_INS_VPBLENDMQ = 1001
'     UC_X86_INS_VPBLENDMW = 1002
'     UC_X86_INS_VPBLENDVB = 1003
'     UC_X86_INS_VPBLENDW = 1004
'     UC_X86_INS_VPBROADCASTB = 1005
'     UC_X86_INS_VPBROADCASTD = 1006
'     UC_X86_INS_VPBROADCASTMB2Q = 1007
'     UC_X86_INS_VPBROADCASTMW2D = 1008
'     UC_X86_INS_VPBROADCASTQ = 1009
'     UC_X86_INS_VPBROADCASTW = 1010
'     UC_X86_INS_VPCLMULQDQ = 1011
'     UC_X86_INS_VPCMOV = 1012
'     UC_X86_INS_VPCMPB = 1013
'     UC_X86_INS_VPCMPD = 1014
'     UC_X86_INS_VPCMPEQB = 1015
'     UC_X86_INS_VPCMPEQD = 1016
'     UC_X86_INS_VPCMPEQQ = 1017
'     UC_X86_INS_VPCMPEQW = 1018
'     UC_X86_INS_VPCMPESTRI = 1019
'     UC_X86_INS_VPCMPESTRM = 1020
'     UC_X86_INS_VPCMPGTB = 1021
'     UC_X86_INS_VPCMPGTD = 1022
'     UC_X86_INS_VPCMPGTQ = 1023
'     UC_X86_INS_VPCMPGTW = 1024
'     UC_X86_INS_VPCMPISTRI = 1025
'     UC_X86_INS_VPCMPISTRM = 1026
'     UC_X86_INS_VPCMPQ = 1027
'     UC_X86_INS_VPCMPUB = 1028
'     UC_X86_INS_VPCMPUD = 1029
'     UC_X86_INS_VPCMPUQ = 1030
'     UC_X86_INS_VPCMPUW = 1031
'     UC_X86_INS_VPCMPW = 1032
'     UC_X86_INS_VPCOMB = 1033
'     UC_X86_INS_VPCOMD = 1034
'     UC_X86_INS_VPCOMPRESSD = 1035
'     UC_X86_INS_VPCOMPRESSQ = 1036
'     UC_X86_INS_VPCOMQ = 1037
'     UC_X86_INS_VPCOMUB = 1038
'     UC_X86_INS_VPCOMUD = 1039
'     UC_X86_INS_VPCOMUQ = 1040
'     UC_X86_INS_VPCOMUW = 1041
'     UC_X86_INS_VPCOMW = 1042
'     UC_X86_INS_VPCONFLICTD = 1043
'     UC_X86_INS_VPCONFLICTQ = 1044
'     UC_X86_INS_VPERM2F128 = 1045
'     UC_X86_INS_VPERM2I128 = 1046
'     UC_X86_INS_VPERMD = 1047
'     UC_X86_INS_VPERMI2D = 1048
'     UC_X86_INS_VPERMI2PD = 1049
'     UC_X86_INS_VPERMI2PS = 1050
'     UC_X86_INS_VPERMI2Q = 1051
'     UC_X86_INS_VPERMIL2PD = 1052
'     UC_X86_INS_VPERMIL2PS = 1053
'     UC_X86_INS_VPERMILPD = 1054
'     UC_X86_INS_VPERMILPS = 1055
'     UC_X86_INS_VPERMPD = 1056
'     UC_X86_INS_VPERMPS = 1057
'     UC_X86_INS_VPERMQ = 1058
'     UC_X86_INS_VPERMT2D = 1059
'     UC_X86_INS_VPERMT2PD = 1060
'     UC_X86_INS_VPERMT2PS = 1061
'     UC_X86_INS_VPERMT2Q = 1062
'     UC_X86_INS_VPEXPANDD = 1063
'     UC_X86_INS_VPEXPANDQ = 1064
'     UC_X86_INS_VPEXTRB = 1065
'     UC_X86_INS_VPEXTRD = 1066
'     UC_X86_INS_VPEXTRQ = 1067
'     UC_X86_INS_VPEXTRW = 1068
'     UC_X86_INS_VPGATHERDD = 1069
'     UC_X86_INS_VPGATHERDQ = 1070
'     UC_X86_INS_VPGATHERQD = 1071
'     UC_X86_INS_VPGATHERQQ = 1072
'     UC_X86_INS_VPHADDBD = 1073
'     UC_X86_INS_VPHADDBQ = 1074
'     UC_X86_INS_VPHADDBW = 1075
'     UC_X86_INS_VPHADDDQ = 1076
'     UC_X86_INS_VPHADDD = 1077
'     UC_X86_INS_VPHADDSW = 1078
'     UC_X86_INS_VPHADDUBD = 1079
'     UC_X86_INS_VPHADDUBQ = 1080
'     UC_X86_INS_VPHADDUBW = 1081
'     UC_X86_INS_VPHADDUDQ = 1082
'     UC_X86_INS_VPHADDUWD = 1083
'     UC_X86_INS_VPHADDUWQ = 1084
'     UC_X86_INS_VPHADDWD = 1085
'     UC_X86_INS_VPHADDWQ = 1086
'     UC_X86_INS_VPHADDW = 1087
'     UC_X86_INS_VPHMINPOSUW = 1088
'     UC_X86_INS_VPHSUBBW = 1089
'     UC_X86_INS_VPHSUBDQ = 1090
'     UC_X86_INS_VPHSUBD = 1091
'     UC_X86_INS_VPHSUBSW = 1092
'     UC_X86_INS_VPHSUBWD = 1093
'     UC_X86_INS_VPHSUBW = 1094
'     UC_X86_INS_VPINSRB = 1095
'     UC_X86_INS_VPINSRD = 1096
'     UC_X86_INS_VPINSRQ = 1097
'     UC_X86_INS_VPINSRW = 1098
'     UC_X86_INS_VPLZCNTD = 1099
'     UC_X86_INS_VPLZCNTQ = 1100
'     UC_X86_INS_VPMACSDD = 1101
'     UC_X86_INS_VPMACSDQH = 1102
'     UC_X86_INS_VPMACSDQL = 1103
'     UC_X86_INS_VPMACSSDD = 1104
'     UC_X86_INS_VPMACSSDQH = 1105
'     UC_X86_INS_VPMACSSDQL = 1106
'     UC_X86_INS_VPMACSSWD = 1107
'     UC_X86_INS_VPMACSSWW = 1108
'     UC_X86_INS_VPMACSWD = 1109
'     UC_X86_INS_VPMACSWW = 1110
'     UC_X86_INS_VPMADCSSWD = 1111
'     UC_X86_INS_VPMADCSWD = 1112
'     UC_X86_INS_VPMADDUBSW = 1113
'     UC_X86_INS_VPMADDWD = 1114
'     UC_X86_INS_VPMASKMOVD = 1115
'     UC_X86_INS_VPMASKMOVQ = 1116
'     UC_X86_INS_VPMAXSB = 1117
'     UC_X86_INS_VPMAXSD = 1118
'     UC_X86_INS_VPMAXSQ = 1119
'     UC_X86_INS_VPMAXSW = 1120
'     UC_X86_INS_VPMAXUB = 1121
'     UC_X86_INS_VPMAXUD = 1122
'     UC_X86_INS_VPMAXUQ = 1123
'     UC_X86_INS_VPMAXUW = 1124
'     UC_X86_INS_VPMINSB = 1125
'     UC_X86_INS_VPMINSD = 1126
'     UC_X86_INS_VPMINSQ = 1127
'     UC_X86_INS_VPMINSW = 1128
'     UC_X86_INS_VPMINUB = 1129
'     UC_X86_INS_VPMINUD = 1130
'     UC_X86_INS_VPMINUQ = 1131
'     UC_X86_INS_VPMINUW = 1132
'     UC_X86_INS_VPMOVDB = 1133
'     UC_X86_INS_VPMOVDW = 1134
'     UC_X86_INS_VPMOVM2B = 1135
'     UC_X86_INS_VPMOVM2D = 1136
'     UC_X86_INS_VPMOVM2Q = 1137
'     UC_X86_INS_VPMOVM2W = 1138
'     UC_X86_INS_VPMOVMSKB = 1139
'     UC_X86_INS_VPMOVQB = 1140
'     UC_X86_INS_VPMOVQD = 1141
'     UC_X86_INS_VPMOVQW = 1142
'     UC_X86_INS_VPMOVSDB = 1143
'     UC_X86_INS_VPMOVSDW = 1144
'     UC_X86_INS_VPMOVSQB = 1145
'     UC_X86_INS_VPMOVSQD = 1146
'     UC_X86_INS_VPMOVSQW = 1147
'     UC_X86_INS_VPMOVSXBD = 1148
'     UC_X86_INS_VPMOVSXBQ = 1149
'     UC_X86_INS_VPMOVSXBW = 1150
'     UC_X86_INS_VPMOVSXDQ = 1151
'     UC_X86_INS_VPMOVSXWD = 1152
'     UC_X86_INS_VPMOVSXWQ = 1153
'     UC_X86_INS_VPMOVUSDB = 1154
'     UC_X86_INS_VPMOVUSDW = 1155
'     UC_X86_INS_VPMOVUSQB = 1156
'     UC_X86_INS_VPMOVUSQD = 1157
'     UC_X86_INS_VPMOVUSQW = 1158
'     UC_X86_INS_VPMOVZXBD = 1159
'     UC_X86_INS_VPMOVZXBQ = 1160
'     UC_X86_INS_VPMOVZXBW = 1161
'     UC_X86_INS_VPMOVZXDQ = 1162
'     UC_X86_INS_VPMOVZXWD = 1163
'     UC_X86_INS_VPMOVZXWQ = 1164
'     UC_X86_INS_VPMULDQ = 1165
'     UC_X86_INS_VPMULHRSW = 1166
'     UC_X86_INS_VPMULHUW = 1167
'     UC_X86_INS_VPMULHW = 1168
'     UC_X86_INS_VPMULLD = 1169
'     UC_X86_INS_VPMULLQ = 1170
'     UC_X86_INS_VPMULLW = 1171
'     UC_X86_INS_VPMULUDQ = 1172
'     UC_X86_INS_VPORD = 1173
'     UC_X86_INS_VPORQ = 1174
'     UC_X86_INS_VPOR = 1175
'     UC_X86_INS_VPPERM = 1176
'     UC_X86_INS_VPROTB = 1177
'     UC_X86_INS_VPROTD = 1178
'     UC_X86_INS_VPROTQ = 1179
'     UC_X86_INS_VPROTW = 1180
'     UC_X86_INS_VPSADBW = 1181
'     UC_X86_INS_VPSCATTERDD = 1182
'     UC_X86_INS_VPSCATTERDQ = 1183
'     UC_X86_INS_VPSCATTERQD = 1184
'     UC_X86_INS_VPSCATTERQQ = 1185
'     UC_X86_INS_VPSHAB = 1186
'     UC_X86_INS_VPSHAD = 1187
'     UC_X86_INS_VPSHAQ = 1188
'     UC_X86_INS_VPSHAW = 1189
'     UC_X86_INS_VPSHLB = 1190
'     UC_X86_INS_VPSHLD = 1191
'     UC_X86_INS_VPSHLQ = 1192
'     UC_X86_INS_VPSHLW = 1193
'     UC_X86_INS_VPSHUFB = 1194
'     UC_X86_INS_VPSHUFD = 1195
'     UC_X86_INS_VPSHUFHW = 1196
'     UC_X86_INS_VPSHUFLW = 1197
'     UC_X86_INS_VPSIGNB = 1198
'     UC_X86_INS_VPSIGND = 1199
'     UC_X86_INS_VPSIGNW = 1200
'     UC_X86_INS_VPSLLDQ = 1201
'     UC_X86_INS_VPSLLD = 1202
'     UC_X86_INS_VPSLLQ = 1203
'     UC_X86_INS_VPSLLVD = 1204
'     UC_X86_INS_VPSLLVQ = 1205
'     UC_X86_INS_VPSLLW = 1206
'     UC_X86_INS_VPSRAD = 1207
'     UC_X86_INS_VPSRAQ = 1208
'     UC_X86_INS_VPSRAVD = 1209
'     UC_X86_INS_VPSRAVQ = 1210
'     UC_X86_INS_VPSRAW = 1211
'     UC_X86_INS_VPSRLDQ = 1212
'     UC_X86_INS_VPSRLD = 1213
'     UC_X86_INS_VPSRLQ = 1214
'     UC_X86_INS_VPSRLVD = 1215
'     UC_X86_INS_VPSRLVQ = 1216
'     UC_X86_INS_VPSRLW = 1217
'     UC_X86_INS_VPSUBB = 1218
'     UC_X86_INS_VPSUBD = 1219
'     UC_X86_INS_VPSUBQ = 1220
'     UC_X86_INS_VPSUBSB = 1221
'     UC_X86_INS_VPSUBSW = 1222
'     UC_X86_INS_VPSUBUSB = 1223
'     UC_X86_INS_VPSUBUSW = 1224
'     UC_X86_INS_VPSUBW = 1225
'     UC_X86_INS_VPTESTMD = 1226
'     UC_X86_INS_VPTESTMQ = 1227
'     UC_X86_INS_VPTESTNMD = 1228
'     UC_X86_INS_VPTESTNMQ = 1229
'     UC_X86_INS_VPTEST = 1230
'     UC_X86_INS_VPUNPCKHBW = 1231
'     UC_X86_INS_VPUNPCKHDQ = 1232
'     UC_X86_INS_VPUNPCKHQDQ = 1233
'     UC_X86_INS_VPUNPCKHWD = 1234
'     UC_X86_INS_VPUNPCKLBW = 1235
'     UC_X86_INS_VPUNPCKLDQ = 1236
'     UC_X86_INS_VPUNPCKLQDQ = 1237
'     UC_X86_INS_VPUNPCKLWD = 1238
'     UC_X86_INS_VPXORD = 1239
'     UC_X86_INS_VPXORQ = 1240
'     UC_X86_INS_VPXOR = 1241
'     UC_X86_INS_VRCP14PD = 1242
'     UC_X86_INS_VRCP14PS = 1243
'     UC_X86_INS_VRCP14SD = 1244
'     UC_X86_INS_VRCP14SS = 1245
'     UC_X86_INS_VRCP28PD = 1246
'     UC_X86_INS_VRCP28PS = 1247
'     UC_X86_INS_VRCP28SD = 1248
'     UC_X86_INS_VRCP28SS = 1249
'     UC_X86_INS_VRCPPS = 1250
'     UC_X86_INS_VRCPSS = 1251
'     UC_X86_INS_VRNDSCALEPD = 1252
'     UC_X86_INS_VRNDSCALEPS = 1253
'     UC_X86_INS_VRNDSCALESD = 1254
'     UC_X86_INS_VRNDSCALESS = 1255
'     UC_X86_INS_VROUNDPD = 1256
'     UC_X86_INS_VROUNDPS = 1257
'     UC_X86_INS_VROUNDSD = 1258
'     UC_X86_INS_VROUNDSS = 1259
'     UC_X86_INS_VRSQRT14PD = 1260
'     UC_X86_INS_VRSQRT14PS = 1261
'     UC_X86_INS_VRSQRT14SD = 1262
'     UC_X86_INS_VRSQRT14SS = 1263
'     UC_X86_INS_VRSQRT28PD = 1264
'     UC_X86_INS_VRSQRT28PS = 1265
'     UC_X86_INS_VRSQRT28SD = 1266
'     UC_X86_INS_VRSQRT28SS = 1267
'     UC_X86_INS_VRSQRTPS = 1268
'     UC_X86_INS_VRSQRTSS = 1269
'     UC_X86_INS_VSCATTERDPD = 1270
'     UC_X86_INS_VSCATTERDPS = 1271
'     UC_X86_INS_VSCATTERPF0DPD = 1272
'     UC_X86_INS_VSCATTERPF0DPS = 1273
'     UC_X86_INS_VSCATTERPF0QPD = 1274
'     UC_X86_INS_VSCATTERPF0QPS = 1275
'     UC_X86_INS_VSCATTERPF1DPD = 1276
'     UC_X86_INS_VSCATTERPF1DPS = 1277
'     UC_X86_INS_VSCATTERPF1QPD = 1278
'     UC_X86_INS_VSCATTERPF1QPS = 1279
'     UC_X86_INS_VSCATTERQPD = 1280
'     UC_X86_INS_VSCATTERQPS = 1281
'     UC_X86_INS_VSHUFPD = 1282
'     UC_X86_INS_VSHUFPS = 1283
'     UC_X86_INS_VSQRTPD = 1284
'     UC_X86_INS_VSQRTPS = 1285
'     UC_X86_INS_VSQRTSD = 1286
'     UC_X86_INS_VSQRTSS = 1287
'     UC_X86_INS_VSTMXCSR = 1288
'     UC_X86_INS_VSUBPD = 1289
'     UC_X86_INS_VSUBPS = 1290
'     UC_X86_INS_VSUBSD = 1291
'     UC_X86_INS_VSUBSS = 1292
'     UC_X86_INS_VTESTPD = 1293
'     UC_X86_INS_VTESTPS = 1294
'     UC_X86_INS_VUNPCKHPD = 1295
'     UC_X86_INS_VUNPCKHPS = 1296
'     UC_X86_INS_VUNPCKLPD = 1297
'     UC_X86_INS_VUNPCKLPS = 1298
'     UC_X86_INS_VZEROALL = 1299
'     UC_X86_INS_VZEROUPPER = 1300
'     UC_X86_INS_WAIT = 1301
'     UC_X86_INS_WBINVD = 1302
'     UC_X86_INS_WRFSBASE = 1303
'     UC_X86_INS_WRGSBASE = 1304
'     UC_X86_INS_WRMSR = 1305
'     UC_X86_INS_XABORT = 1306
'     UC_X86_INS_XACQUIRE = 1307
'     UC_X86_INS_XBEGIN = 1308
'     UC_X86_INS_XCHG = 1309
'     UC_X86_INS_XCRYPTCBC = 1310
'     UC_X86_INS_XCRYPTCFB = 1311
'     UC_X86_INS_XCRYPTCTR = 1312
'     UC_X86_INS_XCRYPTECB = 1313
'     UC_X86_INS_XCRYPTOFB = 1314
'     UC_X86_INS_XEND = 1315
'     UC_X86_INS_XGETBV = 1316
'     UC_X86_INS_XLATB = 1317
'     UC_X86_INS_XRELEASE = 1318
'     UC_X86_INS_XRSTOR = 1319
'     UC_X86_INS_XRSTOR64 = 1320
'     UC_X86_INS_XRSTORS = 1321
'     UC_X86_INS_XRSTORS64 = 1322
'     UC_X86_INS_XSAVE = 1323
'     UC_X86_INS_XSAVE64 = 1324
'     UC_X86_INS_XSAVEC = 1325
'     UC_X86_INS_XSAVEC64 = 1326
'     UC_X86_INS_XSAVEOPT = 1327
'     UC_X86_INS_XSAVEOPT64 = 1328
'     UC_X86_INS_XSAVES = 1329
'     UC_X86_INS_XSAVES64 = 1330
'     UC_X86_INS_XSETBV = 1331
'     UC_X86_INS_XSHA1 = 1332
'     UC_X86_INS_XSHA256 = 1333
'     UC_X86_INS_XSTORE = 1334
'     UC_X86_INS_XTEST = 1335
'     UC_X86_INS_FDISI8087_NOP = 1336
'     UC_X86_INS_FENI8087_NOP = 1337
'     UC_X86_INS_ENDING = 1338
'End Enum

'-- [x86 specific] ---------------

'// Memory-Management Register for instructions IDTR, GDTR, LDTR, TR.
'// Borrow from SegmentCache in qemu/target-i386/cpu.h
'typedef struct uc_x86_mmr {
'    uint16_t selector;  /* not used by GDTR and IDTR */
'    uint64_t base;      /* handle 32 or 64 bit CPUs */
'    uint32_t limit;
'    uint32_t flags;     /* not used by GDTR and IDTR */
'} uc_x86_mmr;
'
'// Callback function for tracing SYSCALL/SYSENTER (for uc_hook_intr())
'// @user_data: user data passed to tracing APIs.
'typedef void (*uc_cb_insn_syscall_t)(struct uc_struct *uc, void *user_data);

'--------------------------------

'// Hook type for all events of unmapped memory access
'#define UC_HOOK_MEM_UNMAPPED (UC_HOOK_MEM_READ_UNMAPPED + UC_HOOK_MEM_WRITE_UNMAPPED + UC_HOOK_MEM_FETCH_UNMAPPED)
'// Hook type for all events of illegal protected memory access
'#define UC_HOOK_MEM_PROT (UC_HOOK_MEM_READ_PROT + UC_HOOK_MEM_WRITE_PROT + UC_HOOK_MEM_FETCH_PROT)
'// Hook type for all events of illegal read memory access
'#define UC_HOOK_MEM_READ_INVALID (UC_HOOK_MEM_READ_PROT + UC_HOOK_MEM_READ_UNMAPPED)
'// Hook type for all events of illegal write memory access
'#define UC_HOOK_MEM_WRITE_INVALID (UC_HOOK_MEM_WRITE_PROT + UC_HOOK_MEM_WRITE_UNMAPPED)
'// Hook type for all events of illegal fetch memory access
'#define UC_HOOK_MEM_FETCH_INVALID (UC_HOOK_MEM_FETCH_PROT + UC_HOOK_MEM_FETCH_UNMAPPED)
'// Hook type for all events of illegal memory access
'#define UC_HOOK_MEM_INVALID (UC_HOOK_MEM_UNMAPPED + UC_HOOK_MEM_PROT)
'// Hook type for all events of valid memory access
'#define UC_HOOK_MEM_VALID (UC_HOOK_MEM_READ + UC_HOOK_MEM_WRITE + UC_HOOK_MEM_FETCH)



'/*
'  Callback function for tracing code (UC_HOOK_CODE & UC_HOOK_BLOCK)
'
'  @address: address where the code is being executed
'  @size: size of machine instruction(s) being executed, or 0 when size is unknown
'  @user_data: user data passed to tracing APIs.
'*/
'typedef void (*uc_cb_hookcode_t)(uc_engine *uc, uint64_t address, uint32_t size, void *user_data);
'  public sub code_hook(byval uc as long , byval address as currency, byval size as long, byval user_data as long)
'
'/*
'  Callback function for tracing interrupts (for uc_hook_intr())
'
'  @intno: interrupt number
'  @user_data: user data passed to tracing APIs.
'*/
'typedef void (*uc_cb_hookintr_t)(uc_engine *uc, uint32_t intno, void *user_data);
'
'/*
'  Callback function for tracing IN instruction of X86
'
'  @port: port number
'  @size: data size (1/2/4) to be read from this port
'  @user_data: user data passed to tracing APIs.
'*/
'typedef uint32_t (*uc_cb_insn_in_t)(uc_engine *uc, uint32_t port, int size, void *user_data);
'
'/*
'  Callback function for OUT instruction of X86
'
'  @port: port number
'  @size: data size (1/2/4) to be written to this port
'  @value: data value to be written to this port
'*/
'typedef void (*uc_cb_insn_out_t)(uc_engine *uc, uint32_t port, int size, uint32_t value, void *user_data);
'
'/*
'  Callback function for hooking memory (UC_MEM_READ, UC_MEM_WRITE & UC_MEM_FETCH)
'
'  @type: this memory is being READ, or WRITE
'  @address: address where the code is being executed
'  @size: size of data being read or written
'  @value: value of data being written to memory, or irrelevant if type = READ.
'  @user_data: user data passed to tracing APIs
'*/
'typedef void (*uc_cb_hookmem_t)(uc_engine *uc, uc_mem_type type,
'        uint64_t address, int size, int64_t value, void *user_data);
'
'/*
'  Callback function for handling invalid memory access events (UC_MEM_*_UNMAPPED and
'    UC_MEM_*PROT events)
'
'  @type: this memory is being READ, or WRITE
'  @address: address where the code is being executed
'  @size: size of data being read or written
'  @value: value of data being written to memory, or irrelevant if type = READ.
'  @user_data: user data passed to tracing APIs
'
'  @return: return true to continue, or false to stop program (due to invalid memory).
'*/
'typedef bool (*uc_cb_eventmem_t)(uc_engine *uc, uc_mem_type type,
'        uint64_t address, int size, int64_t value, void *user_data);

'/*
'  Memory region mapped by uc_mem_map() and uc_mem_map_ptr()
'  Retrieve the list of memory regions with uc_mem_regions()
'*/
'typedef struct uc_mem_region {
'    uint64_t begin; // begin address of the region (inclusive)
'    uint64_t end;   // end address of the region (inclusive)
'    uint32_t perms; // memory permissions of the region
'} uc_mem_region;
'
'// All type of queries for uc_query() API.
'typedef enum uc_query_type {
'    // Dynamically query current hardware mode.
'    UC_QUERY_MODE = 1,
'    UC_QUERY_PAGE_SIZE,
'} uc_query_type;



Public Declare Function ucs_dynload Lib "ucvbshim.dll" (ByVal path As String) As Long



'/*
' Return combined API version & major and minor version numbers.
'
' @major: major number of API version
' @minor: minor number of API version
'
' @return hexical number as (major << 8 | minor), which encodes both
'     major & minor versions.
'     NOTE: This returned value can be compared with version number made
'     with macro UC_MAKE_VERSION
'
' For example, second API version would return 1 in @major, and 1 in @minor
' The return value would be 0x0101
'
' NOTE: if you only care about returned value, but not major and minor values,
' set both @major & @minor arguments to NULL.
'*/
'UNICORN_EXPORT
'unsigned int uc_version(unsigned int *major, unsigned int *minor);
Public Declare Function ucs_version Lib "ucvbshim.dll" (ByRef major As Long, ByRef minor As Long) As Long


'
'
'/*
' Determine if the given architecture is supported by this library.
'
' @arch: architecture type (UC_ARCH_*)
'
' @return True if this library supports the given arch.
'*/
'UNICORN_EXPORT
'bool uc_arch_supported(uc_arch arch);
Public Declare Function ucs_arch_supported Lib "ucvbshim.dll" (ByVal arch As uc_arch) As Long


'/*
' Create new instance of unicorn engine.
'
' @arch: architecture type (UC_ARCH_*)
' @mode: hardware mode. This is combined of UC_MODE_*
' @uc: pointer to uc_engine, which will be updated at return time
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_open(uc_arch arch, uc_mode mode, uc_engine **uc);
Public Declare Function ucs_open Lib "ucvbshim.dll" (ByVal arch As uc_arch, ByVal mode As uc_mode, ByRef hEngine As Long) As uc_err


'/*
' Close UC instance: MUST do to release the handle when it is not used anymore.
' NOTE: this must be called only when there is no longer usage of Unicorn.
' The reason is the this API releases some cached memory, thus access to any
' Unicorn API after uc_close() might crash your application.
' After this, @uc is invalid, and nolonger usable.
'
' @uc: pointer to a handle returned by uc_open()
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_close(uc_engine *uc);
Public Declare Function ucs_close Lib "ucvbshim.dll" (ByVal hEngine As Long) As uc_err

'
'/*
' Query internal status of engine.
'
' @uc: handle returned by uc_open()
' @type: query type. See uc_query_type
'
' @result: save the internal status queried
'
' @return: error code of uc_err enum type (UC_ERR_*, see above)
'*/
'// All type of queries for uc_query() API.
'typedef enum uc_query_type {
'    // Dynamically query current hardware mode.
'    UC_QUERY_MODE = 1,
'    UC_QUERY_PAGE_SIZE,
'} uc_query_type;
'UNICORN_EXPORT
'uc_err uc_query(uc_engine *uc, uc_query_type type, size_t *result);



'/*
' Report the last error number when some API function fail.
' Like glibc's errno, uc_errno might not retain its old value once accessed.
'
' @uc: handle returned by uc_open()
'
' @return: error code of uc_err enum type (UC_ERR_*, see above)
'*/
'UNICORN_EXPORT
'uc_err uc_errno(uc_engine *uc);
Public Declare Function ucs_errno Lib "ucvbshim.dll" (ByVal hEngine As Long) As uc_err


'
'/*
' Return a string describing given error code.
'
' @code: error code (see UC_ERR_* above)
'
' @return: returns a pointer to a string that describes the error code
'   passed in the argument @code
' */
'UNICORN_EXPORT
'const char *uc_strerror(uc_err code);
Public Declare Function ucs_strerror Lib "ucvbshim.dll" (ByVal code As uc_err) As Long



'/*
' Write to register.
'
' @uc: handle returned by uc_open()
' @regid:  register ID that is to be modified.
' @value:  pointer to the value that will set to register @regid
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_reg_write(uc_engine *uc, int regid, const void *value);
Public Declare Function ucs_reg_write Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal regid As uc_x86_reg, ByRef value As Long) As uc_err


'/*
' Read register value.
'
' @uc: handle returned by uc_open()
' @regid:  register ID that is to be retrieved.
' @value:  pointer to a variable storing the register value.
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_reg_read(uc_engine *uc, int regid, void *value);
Public Declare Function ucs_reg_read Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal regid As uc_x86_reg, ByRef value As Long) As uc_err



'/*
' Write multiple register values.
'
' @uc: handle returned by uc_open()
' @rges:  array of register IDs to store
' @value: pointer to array of register values
' @count: length of both *regs and *vals
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_reg_write_batch(uc_engine *uc, int *regs, void *const *vals, int count);



'
'/*
' Read multiple register values.
'
' @uc: handle returned by uc_open()
' @rges:  array of register IDs to retrieve
' @value: pointer to array of values to hold registers
' @count: length of both *regs and *vals
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_reg_read_batch(uc_engine *uc, int *regs, void **vals, int count);



'/*
' Write to a range of bytes in memory.
'
' @uc: handle returned by uc_open()
' @address: starting memory address of bytes to set.
' @bytes:   pointer to a variable containing data to be written to memory.
' @size:   size of memory to write to.
'
' NOTE: @bytes must be big enough to contain @size bytes.
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_mem_write(uc_engine *uc, uint64_t address, const void *bytes, size_t size);
Public Declare Function ucs_mem_write Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal addr As Currency, ByRef b As Byte, ByVal size As Long) As uc_err



'/*
' Read a range of bytes in memory.
'
' @uc: handle returned by uc_open()
' @address: starting memory address of bytes to get.
' @bytes:   pointer to a variable containing data copied from memory.
' @size:   size of memory to read.
'
' NOTE: @bytes must be big enough to contain @size bytes.
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_mem_read(uc_engine *uc, uint64_t address, void *bytes, size_t size);
Public Declare Function ucs_mem_read Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal addr As Currency, ByRef b As Byte, ByVal size As Long) As uc_err




'/*
' Emulate machine code in a specific duration of time.
'
' @uc: handle returned by uc_open()
' @begin: address where emulation starts
' @until: address where emulation stops (i.e when this address is hit)
' @timeout: duration to emulate the code (in microseconds). When this value is 0,
'        we will emulate the code in infinite time, until the code is finished.
' @count: the number of instructions to be emulated. When this value is 0,
'        we will emulate all the code available, until the code is finished.
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_emu_start(uc_engine *uc, uint64_t begin, uint64_t until, uint64_t timeout, size_t count);
Public Declare Function ucs_emu_start Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal startAt As Currency, ByVal endAt As Currency, ByVal timeout As Currency, ByVal count As Long) As uc_err


'
'/*
' Stop emulation (which was started by uc_emu_start() API.
' This is typically called from callback functions registered via tracing APIs.
' NOTE: for now, this will stop the execution only after the current block.
'
' @uc: handle returned by uc_open()
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_emu_stop(uc_engine *uc);
Public Declare Function ucs_emu_stop Lib "ucvbshim.dll" (ByVal hEngine As Long) As uc_err



'/*
' Register callback for a hook event.
' The callback will be run when the hook event is hit.
'
' @uc: handle returned by uc_open()
' @hh: hook handle returned from this registration. To be used in uc_hook_del() API
' @type: hook type
' @callback: callback to be run when instruction is hit
' @user_data: user-defined data. This will be passed to callback function in its
'      last argument @user_data
' @begin: start address of the area where the callback is effect (inclusive)
' @end: end address of the area where the callback is effect (inclusive)
'   NOTE 1: the callback is called only if related address is in range [@begin, @end]
'   NOTE 2: if @begin > @end, callback is called whenever this hook type is triggered
' @...: variable arguments (depending on @type)
'   NOTE: if @type = UC_HOOK_INSN, this is the instruction ID (ex: UC_X86_INS_OUT)
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err __stdcall ucs_hook_add(uc_engine *uc, uc_hook *hh, int type, void *callback, void *user_data, uint64_t begin, uint64_t end, ...)
'
'note vb6 does not support variable length arguments to api declares so UC_HOOK_INSN would require a seperate declare and stub
'also note that the callback is not used directly, it is proxied through a cdecl stub
'since the hook flags can be different combos, we pass in a catagory for simplicity in selecting which c callback to use..(bit sloppy but easy)
Public Declare Function ucs_hook_add Lib "ucvbshim.dll" (ByVal hEngine As Long, ByRef hHook As Long, ByVal hType As uc_hook_type, ByVal callback As Long, ByVal user_data As Long, ByVal beginAt As Currency, ByVal endAt As Currency, ByVal catagory As Long, Optional ByVal inst_id As Long = 0) As uc_err


'/*
' Unregister (remove) a hook callback.
' This API removes the hook callback registered by uc_hook_add().
' NOTE: this should be called only when you no longer want to trace.
' After this, @hh is invalid, and nolonger usable.
'
' @uc: handle returned by uc_open()
' @hh: handle returned by uc_hook_add()
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_hook_del(uc_engine *uc, uc_hook hh);
Public Declare Function ucs_hook_del Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal hHook As Long) As uc_err



'/*
' Map memory in for emulation.
' This API adds a memory region that can be used by emulation.
'
' @uc: handle returned by uc_open()
' @address: starting address of the new memory region to be mapped in.
'    This address must be aligned to 4KB, or this will return with UC_ERR_ARG error.
' @size: size of the new memory region to be mapped in.
'    This size must be multiple of 4KB, or this will return with UC_ERR_ARG error.
' @perms: Permissions for the newly mapped region.
'    This must be some combination of UC_PROT_READ | UC_PROT_WRITE | UC_PROT_EXEC,
'    or this will return with UC_ERR_ARG error.
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_mem_map(uc_engine *uc, uint64_t address, size_t size, uint32_t perms);
Public Declare Function ucs_mem_map Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal addr As Currency, ByVal size As Long, ByVal perms As uc_prot) As uc_err



'/*
' Map existing host memory in for emulation.
' This API adds a memory region that can be used by emulation.
'
' @uc: handle returned by uc_open()
' @address: starting address of the new memory region to be mapped in.
'    This address must be aligned to 4KB, or this will return with UC_ERR_ARG error.
' @size: size of the new memory region to be mapped in.
'    This size must be multiple of 4KB, or this will return with UC_ERR_ARG error.
' @perms: Permissions for the newly mapped region.
'    This must be some combination of UC_PROT_READ | UC_PROT_WRITE | UC_PROT_EXEC,
'    or this will return with UC_ERR_ARG error.
' @ptr: pointer to host memory backing the newly mapped memory. This host memory is
'    expected to be an equal or larger size than provided, and be mapped with at
'    least PROT_READ | PROT_WRITE. If it is not, the resulting behavior is undefined.
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_mem_map_ptr(uc_engine *uc, uint64_t address, size_t size, uint32_t perms, void *ptr);
Public Declare Function ucs_mem_map_ptr Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal addr As Currency, ByVal size As Long, ByVal perms As uc_prot, ByVal ptr As Long) As uc_err



'/*
' Unmap a region of emulation memory.
' This API deletes a memory mapping from the emulation memory space.
'
' @uc: handle returned by uc_open()
' @address: starting address of the memory region to be unmapped.
'    This address must be aligned to 4KB, or this will return with UC_ERR_ARG error.
' @size: size of the memory region to be modified.
'    This size must be multiple of 4KB, or this will return with UC_ERR_ARG error.
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_mem_unmap(uc_engine *uc, uint64_t address, size_t size);
Public Declare Function ucs_mem_unmap Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal addr As Currency, ByVal size As Long) As uc_err


'/*
' Set memory permissions for emulation memory.
' This API changes permissions on an existing memory region.
'
' @uc: handle returned by uc_open()
' @address: starting address of the memory region to be modified.
'    This address must be aligned to 4KB, or this will return with UC_ERR_ARG error.
' @size: size of the memory region to be modified.
'    This size must be multiple of 4KB, or this will return with UC_ERR_ARG error.
' @perms: New permissions for the mapped region.
'    This must be some combination of UC_PROT_READ | UC_PROT_WRITE | UC_PROT_EXEC,
'    or this will return with UC_ERR_ARG error.
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_mem_protect(uc_engine *uc, uint64_t address, size_t size, uint32_t perms);
Public Declare Function ucs_mem_protect Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal addr As Currency, ByVal size As Long, ByVal perm As uc_prot) As uc_err



'/*
' Retrieve all memory regions mapped by uc_mem_map() and uc_mem_map_ptr()
' This API allocates memory for @regions, and user must free this memory later
' by free() to avoid leaking memory.
' NOTE: memory regions may be splitted by uc_mem_unmap()
'
' @uc: handle returned by uc_open()
' @regions: pointer to an array of uc_mem_region struct. This is allocated by
'   Unicorn, and must be freed by user later
' @count: pointer to number of struct uc_mem_region contained in @regions
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_mem_regions(uc_engine *uc, uc_mem_region **regions, uint32_t *count);
'simplofied for vb use: uc_err __stdcall getMemMap(uc_engine *uc, _CollectionPtr *pColl){

'fills a collection with csv values of all memory regions..
Public Declare Function get_memMap Lib "ucvbshim.dll" (ByVal hEngine As Long, ByRef col As Collection) As uc_err


'/*
' Allocate a region that can be used with uc_context_{save,restore} to perform
' quick save/rollback of the CPU context, which includes registers and some
' internal metadata. Contexts may not be shared across engine instances with
' differing arches or modes.
'
' @uc: handle returned by uc_open()
' @context: pointer to a uc_engine*. This will be updated with the pointer to
'   the new context on successful return of this function.
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_context_alloc(uc_engine *uc, uc_context **context);
Public Declare Function ucs_context_alloc Lib "ucvbshim.dll" (ByVal hEngine As Long, ByRef context As Long) As uc_err



'/*
' Free the resource allocated by uc_context_alloc.
'
' @context: handle returned by uc_context_alloc()
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_free(void* mem);
Public Declare Function ucs_free Lib "ucvbshim.dll" (ByVal mem As Long) As uc_err



'/*
' Save a copy of the internal CPU context.
' This API should be used to efficiently make or update a saved copy of the
' internal CPU state.
'
' @uc: handle returned by uc_open()
' @context: handle returned by uc_context_alloc()
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_context_save(uc_engine *uc, uc_context *context);
Public Declare Function ucs_context_save Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal context As Long) As uc_err



'/*
' Restore the current CPU context from a saved copy.
' This API should be used to roll the CPU context back to a previous
' state saved by uc_context_save().
'
' @uc: handle returned by uc_open()
' @buffer: handle returned by uc_context_alloc that has been used with uc_context_save
'
' @return UC_ERR_OK on success, or other value on failure (refer to uc_err enum
'   for detailed error).
'*/
'UNICORN_EXPORT
'uc_err uc_context_restore(uc_engine *uc, uc_context *context);
Public Declare Function ucs_context_restore Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal context As Long) As uc_err



'uses libdasm to retrieve the 32bit disassembly at a specified va
'int __stdcall disasm_addr(uc_engine *uc, int va, char *str, int bufLen){
Public Declare Function disasm_addr Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal addr As Long, ByVal buf As String, ByVal size As Long) As Long


'simplified access to map and write data to emu memory
'uc_err __stdcall mem_write_block(uc_engine *uc, uint64_t address, void* data, uint32_t size, uint32_t perm){
Public Declare Function mem_write_block Lib "ucvbshim.dll" (ByVal hEngine As Long, ByVal addr As Currency, ByRef data As Byte, ByVal size As Long, ByVal perm As Long) As uc_err

Private Declare Function lstrcpy Lib "kernel32" Alias "lstrcpyA" (ByVal lpString1 As String, ByVal lpString2 As String) As Long
Private Declare Function lstrlen Lib "kernel32" Alias "lstrlenA" (ByVal lpString As Long) As Long

'api version of the below..
'Function err2str(e As uc_err) As String
'    Dim lpStr As Long
'    Dim length As Long
'    Dim buf() As Byte
'
'    lpStr = ucs_strerror(e)
'    If lpStr = 0 Then Exit Function
'
'    length = lstrlen(lpStr)
'    If length = 0 Then Exit Function
'
'    ReDim buf(1 To length)
'    CopyMemory buf(1), ByVal lpStr, length
'
'    err2str2 = StrConv(buf, vbUnicode, &H409)
'
'End Function

Function err2str(e As uc_err) As String
    
    err2str = "Unknown error code: " & e
    
    If e = uc_err_ok Then err2str = "No error: everything was fine"
    If e = UC_ERR_NOMEM Then err2str = "Out-Of-Memory error: uc_open(), uc_emulate()"
    If e = UC_ERR_ARCH Then err2str = "Unsupported architecture: uc_open()"
    If e = UC_ERR_HANDLE Then err2str = "Invalid handle"
    If e = UC_ERR_MODE Then err2str = "Invalid/unsupported mode: uc_open()"
    If e = UC_ERR_VERSION Then err2str = "Unsupported version (bindings)"
    If e = UC_ERR_READ_UNMAPPED Then err2str = "Quit emulation due to READ on unmapped memory: uc_emu_start()"
    If e = UC_ERR_WRITE_UNMAPPED Then err2str = "Quit emulation due to WRITE on unmapped memory: uc_emu_start()"
    If e = UC_ERR_FETCH_UNMAPPED Then err2str = "Quit emulation due to FETCH on unmapped memory: uc_emu_start()"
    If e = UC_ERR_HOOK Then err2str = "Invalid hook type: uc_hook_add()"
    If e = UC_ERR_INSN_INVALID Then err2str = "Quit emulation due to invalid instruction: uc_emu_start()"
    If e = UC_ERR_MAP Then err2str = "Invalid memory mapping: uc_mem_map()"
    If e = UC_ERR_WRITE_PROT Then err2str = "Quit emulation due to UC_MEM_WRITE_PROT violation: uc_emu_start()"
    If e = UC_ERR_READ_PROT Then err2str = "Quit emulation due to UC_MEM_READ_PROT violation: uc_emu_start()"
    If e = UC_ERR_FETCH_PROT Then err2str = "Quit emulation due to UC_MEM_FETCH_PROT violation: uc_emu_start()"
    If e = UC_ERR_ARG Then err2str = "Inavalid argument provided to uc_xxx function (See specific function API)"
    If e = UC_ERR_READ_UNALIGNED Then err2str = "Unaligned read"
    If e = UC_ERR_WRITE_UNALIGNED Then err2str = "Unaligned write"
    If e = UC_ERR_FETCH_UNALIGNED Then err2str = "Unaligned fetch"
    If e = UC_ERR_HOOK_EXIST Then err2str = "hook for this event already existed"
    If e = UC_ERR_RESOURCE Then err2str = "Insufficient resource: uc_emu_start()"
    If e = UC_ERR_EXCEPTION Then err2str = "Unhandled CPU exception"
 
End Function

Function memType2str(t As uc_mem_type)
    
    memType2str = "Unknown memType: " & t
    
    If t = UC_MEM_READ Then memType2str = "Memory is read from"
    If t = uc_mem_write Then memType2str = "Memory is written to"
    If t = UC_MEM_FETCH Then memType2str = "Memory is fetched"
    If t = UC_MEM_READ_UNMAPPED Then memType2str = "Unmapped memory is read from"
    If t = UC_MEM_WRITE_UNMAPPED Then memType2str = "Unmapped memory is written to"
    If t = UC_MEM_FETCH_UNMAPPED Then memType2str = "Unmapped memory is fetched"
    If t = UC_MEM_WRITE_PROT Then memType2str = "Write to write protected, but mapped, memory"
    If t = UC_MEM_READ_PROT Then memType2str = "Read from read protected, but mapped, memory"
    If t = UC_MEM_FETCH_PROT Then memType2str = "Fetch from non-executable, but mapped, memory"
    If t = UC_MEM_READ_AFTER Then memType2str = "Memory is read from (successful access)"
    
End Function

 





'--------------------- [ callback support ] ---------------------------------------------

'so the callbacks must live in a module (vb6 language limitation/safety feature)
'we use a simple lookup mechanism to support multiple instances

Function findInstance(ptr As Long) As ucIntel32
    On Error Resume Next
    Set findInstance = instances("objptr:" & ptr)
End Function

'in case we want to keep userdata for something else..this is just as easy..
Function findInstanceByUc(uc As Long) As ucIntel32
    Dim u As ucIntel32
    For Each u In instances
        If u.uc = uc Then
            Set findInstanceByUc = u
            Exit Function
        End If
    Next
End Function

'typedef void (__stdcall *vb_cb_hookcode_t)   (uc_engine *uc,  uint64_t address,  uint32_t size,    void *user_data);
Public Sub code_hook(ByVal uc As Long, ByVal address As Currency, ByVal size As Long, ByVal user_data As Long)
    Dim u As ucIntel32
    Set u = findInstance(user_data)
    If u Is Nothing Then Exit Sub
    u.internal_code_hook address, size
End Sub

Public Sub block_hook(ByVal uc As Long, ByVal address As Currency, ByVal size As Long, ByVal user_data As Long)
    Dim u As ucIntel32
    Set u = findInstance(user_data)
    If u Is Nothing Then Exit Sub
    u.internal_block_hook address, size
End Sub

'typedef void (*uc_cb_hookmem_t)(uc_engine *uc, uc_mem_type type, uint64_t address, int size, int64_t value, void *user_data);
Public Sub mem_hook(ByVal uc As Long, ByVal t As uc_mem_type, ByVal address As Currency, ByVal size As Long, ByVal value As Currency, ByVal user_data As Long)
    Dim u As ucIntel32
    Set u = findInstance(user_data)
    If u Is Nothing Then Exit Sub
    u.internal_mem_hook t, address, size, value
End Sub

'typedef bool (*uc_cb_eventmem_t)(uc_engine *uc, uc_mem_type type, uint64_t address, int size, int64_t value, void *user_data);
Public Function invalid_mem_hook(ByVal uc As Long, ByVal t As uc_mem_type, ByVal address As Currency, ByVal size As Long, ByVal value As Currency, ByVal user_data As Long) As Long
    'return 0 to stop emulation, 1 to continue
    Dim u As ucIntel32
    Set u = findInstance(user_data)
    If u Is Nothing Then Exit Function
    invalid_mem_hook = u.internal_invalid_mem_hook(t, address, size, value)
End Function

'typedef void (*vb_cb_hookintr_t)(uc_engine *uc,uint32_t intno, void *user_data);
Public Sub interrupt_hook(ByVal uc As Long, ByVal intno As Long, ByVal user_data As Long)
    Dim u As ucIntel32
    Set u = findInstance(user_data)
    If u Is Nothing Then Exit Sub
    u.internal_interrupt_hook intno
End Sub

