; == stub_amd64.asm == 
; nasm -f bin stub_amd64.asm -o stub_amd64; xxd -i stub_amd64 
BITS 64

section .text
global _start

_start:
    mov rbx, 0x401000
find_egg:
    cmp dword [rbx], 0x78474745
    je found
    inc rbx
    jmp find_egg

found:
    add rbx, 4
    mov r8d, [rbx]
    add rbx, 4
    mov r9d, [rbx]
    add rbx, 4

    ; ======= mmap(0x60000000, decomp_size_aligned, PROT_READ | PROT_WRITE, MAP_ANON | MAP_FIXED | MAP_PRIVATE , -1 , 0) =======
    mov rax, 9
    mov rdi, 0x60000000
    mov rsi, r8
    add rsi, 0xfff
    shr rsi, 12
    shl rsi, 12
    mov rdx, 3
    mov r10, 0x22
    mov r8, -1
    xor r9, r9
    syscall

    ; LZ_Uncompress(in, out, insize)
    mov rdi, rbx
    mov rsi, 0x60000000
    mov edx, [0x401008]
   
    ; uncompress + unscramble
    call LZ_Uncompress
    mov dword [0x60000000], 0x464c457f
    
    ; ====== memfd_create("AAA", 0) ======
    push 0x00414141 
    mov rdi, rsp
    xor rsi, rsi                 
    mov rax, 319
    syscall
    mov     r12d, eax  ; fd

    ; ====== write(fd, 0x60000000, decomp_size) ======
    mov     rax, 1                   
    mov     rdi, r12                 ; int fd
    mov     rsi, 0x60000000            ; buf
    xor rdx, rdx
    mov     edx, [0x401004]            ; size
    syscall

    ; ==== execveat(fd, "", argv, envp, AT_EMPTY_PATH) ====
    mov     rax, 322                 
    mov     rdi, r12                 ; fd
    push 0
    mov rsi, rsp                     
    add rsp, 0x18
    mov rdx, rsp                     ; argv
    mov r10, rdx                     
    find_null:
      cmp dword [r10], 0
      je found_null
      add r10, 4
      jmp find_null
    found_null:
      add r10, 8                     ; envp
    mov     r8, 0x1000               ; flags
    syscall

   ; exit
   mov eax, 0x60
   xor rbx, rbx
   syscall

global _LZ_ReadVarSize
_LZ_ReadVarSize:
    push    rbp
    mov     rbp, rsp
    mov     [rbp-0x18], rdi
    mov     [rbp-0x20], rsi
    mov     dword [rbp-0x4], 0
    mov     dword [rbp-0x8], 0

.lzrv_loop:
    mov     rax, [rbp-0x20]
    lea     rdx, [rax+1]
    mov     [rbp-0x20], rdx
    movzx   eax, byte [rax]
    mov     dword [rbp-0xc], eax
    mov     eax, dword [rbp-0x4]
    shl     eax, 7
    mov     edx, eax
    mov     eax, dword [rbp-0xc]
    and     eax, 0x7f
    or      eax, edx
    mov     dword [rbp-0x4], eax
    add     dword [rbp-0x8], 1
    mov     eax, dword [rbp-0xc]
    and     eax, 0x80
    test    eax, eax
    jne     .lzrv_loop

    mov     rax, [rbp-0x18]
    mov     edx, dword [rbp-0x4]
    mov     dword [rax], edx
    mov     eax, dword [rbp-0x8]
    pop     rbp
    ret
global LZ_Uncompress
LZ_Uncompress:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 0x38

    mov     [rbp-0x28], rdi       ; in
    mov     [rbp-0x30], rsi       ; out
    mov     [rbp-0x34], edx       ; insize

    cmp     dword [rbp-0x34], 0
    je      .lzu_end

    mov     rax, [rbp-0x28]
    movzx   eax, byte [rax]
    mov     byte [rbp-0xd], al

    mov     dword [rbp-0x8], 1    ; in_pos = 1
    mov     dword [rbp-0xc], 0    ; out_pos = 0

.lzu_main:
    mov     eax, dword [rbp-0x8]
    lea     edx, [eax+1]
    mov     dword [rbp-0x8], edx
    mov     edx, eax
    mov     rax, [rbp-0x28]
    add     rax, rdx
    movzx   eax, byte [rax]
    mov     byte [rbp-0xe], al
    movzx   eax, byte [rbp-0xe]
    cmp     al, byte [rbp-0xd]
    jne     .lzu_literal

    mov     edx, dword [rbp-0x8]
    mov     rax, [rbp-0x28]
    add     rax, rdx
    movzx   eax, byte [rax]
    test    al, al
    jne     .lzu_compressed

    mov     eax, dword [rbp-0xc]
    lea     edx, [eax+1]
    mov     dword [rbp-0xc], edx
    mov     edx, eax
    mov     rax, [rbp-0x30]
    add     rax, rdx
    movzx   ecx, byte [rbp-0xd]
    ;mov     byte [rax], al
    mov     byte [rax], cl
    add     dword [rbp-0x8], 1
    jmp     .lzu_next

.lzu_compressed:
    mov     edx, dword [rbp-0x8]
    mov     rax, [rbp-0x28]
    add     rax, rdx
    lea     rdi, [rbp-0x14]
    mov     rsi, rax
    call    _LZ_ReadVarSize
    add     dword [rbp-0x8], eax

    mov     edx, dword [rbp-0x8]
    mov     rax, [rbp-0x28]
    add     rax, rdx
    lea     rdi, [rbp-0x18]
    mov     rsi, rax
    call    _LZ_ReadVarSize
    add     dword [rbp-0x8], eax
    mov     dword [rbp-0x4], 0

.lzu_copy_loop:
    mov     eax, dword [rbp-0x18]
    mov     edx, dword [rbp-0xc]
    sub     edx, eax
    mov     rax, [rbp-0x30]
    add     rax, rdx
    movzx   eax, byte [rax]
    mov     ecx, dword [rbp-0xc]
    mov     rdx, [rbp-0x30]
    add     rdx, rcx
    mov     byte [rdx], al
    add     dword [rbp-0xc], 1
    add     dword [rbp-0x4], 1
    mov     eax, dword [rbp-0x14]
    cmp     dword [rbp-0x4], eax
    jb      .lzu_copy_loop
    jmp     .lzu_next

.lzu_literal:
    mov     eax, dword [rbp-0xc]
    lea     edx, [eax+1]
    mov     dword [rbp-0xc], edx
    mov     edx, eax
    mov     rax, [rbp-0x30]
    add     rax, rdx
    movzx   ecx, byte [rbp-0xe]
    mov     byte [rax], cl

.lzu_next:
    mov     eax, dword [rbp-0x8]
    cmp     eax, dword [rbp-0x34]
    jb      .lzu_main

.lzu_end:
    leave
    ret
