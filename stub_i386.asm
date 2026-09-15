; == stub_i386.asm ==
; nasm -f bin stub_i386.asm -o stub_i386; xxd -i stub_i386 
BITS 32

section .text
global _start

_start:
    mov esi, 0x401000           ; base DATA segment
find_egg:                       
    cmp dword [esi], 0x78474745 ; "EGGx"
    je found
    inc esi
    jmp find_egg
found:
    add esi, 4
    mov ebx, [esi]              ; decomp_size
    add esi, 4
    mov edx, [esi]              ; comp_size
    add esi, 4
    mov ecx, ebx                ; ecx = decomp_size

    ; prepare LZ_Uncompress
    push edx       ; insize
    push 0x60000000  ; out
    push esi       ; in

    ; ======= mmap(0x6000000, decomp_size_rounded, PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_FIXED, 0, 0) =======
    add ecx, 0x1000 - 1
    dec ecx
    shr ecx, 12
    shl ecx, 12
    mov eax, 192                ; mmap2 syscall
    mov ebx, 0x60000000           ; vaddr
    mov edx, 3                  ; PROT_READ | PROT_WRITE
    mov esi, 0x22               ; MAP_ANON | MAP_FIXED | MAP_PRIVATE
    mov edi, -1                 ; fd
    xor ebp, ebp                ; offset
    int 0x80

   ; uncompress + unscramble
    call LZ_Uncompress
    mov dword [0x60000000], 0x464c457f

   ;  ======= memfd_create("AAA", 0)  ======= 
    push 0x00414141
    mov eax, 356
    mov ebx, esp
    xor ecx, ecx
    int 0x80
    mov ebx, eax            ; save fd

    ;  ======= write(fd, 0x60000000, decomp_size) =======
    mov eax, 4 
    mov ecx, 0x60000000 
    mov edx, [0x401004]
    int 0x80

    ;  ======= fork() =======
    mov eax, 2
    int 0x80
    cmp eax, 0
    je child_process
    push eax          ; child PID

    ;  ======= waitpid(child_pid, NULL, 0) =======
    mov eax, 0x7
    pop ebx            ; child PID
    xor ecx, ecx       ; status - NULL
    xor edx, edx       ; options = 0
    int  0x80

child_process:
    ; ======== execveat(fd, "", argv, envp, AT_EMPTY_PATH)
    mov eax, 358
    push 0
    mov ecx, esp   ; path
    add esp, 0x18  ; clean
    mov edx, esp   ; argvp
    mov esi, edx
    find_null:
      cmp dword [esi], 0 
      je found_null        
      add esi, 4           
      jmp find_null
    found_null:
      add esi, 4    ; envp
    mov edi, 0x1000
    int 0x80

    ; ======= exit(0) =======
    mov eax, 1
    xor ebx, ebx
    int 0x80

; ==================== LZ_ReadVarSize ====================
_LZ_ReadVarSize:
    push   ebp
    mov    ebp,esp
    sub    esp,0x10
    mov    dword [ebp-0x4],0x0
    mov    dword [ebp-0x8],0x0
.lzrv_loop:
    mov    eax,dword [ebp+0xc]
    lea    edx,[eax+0x1]
    mov    dword [ebp+0xc],edx
    movzx  eax,byte [eax]
    movzx  eax,al
    mov    dword [ebp-0xc],eax
    mov    eax,dword [ebp-0x4]
    shl    eax,0x7
    mov    edx,eax
    mov    eax,dword [ebp-0xc]
    and    eax,0x7f
    or     eax,edx
    mov    dword [ebp-0x4],eax
    add    dword [ebp-0x8],0x1
    mov    eax,dword [ebp-0xc]
    and    eax,0x80
    test   eax,eax
    jne    .lzrv_loop
    mov    eax,dword [ebp+0x8]
    mov    edx,dword [ebp-0x4]
    mov    dword [eax],edx
    mov    eax,dword [ebp-0x8]
    leave
    ret

; ==================== LZ_Uncompress ====================
LZ_Uncompress:
    push   ebp
    mov    ebp,esp
    sub    esp,0x20
    cmp    dword [ebp+0x10],0x0
    je     .lzu_end
    mov    eax,dword [ebp+0x8]
    movzx  eax,byte [eax]
    mov    byte [ebp-0xd],al
    mov    dword [ebp-0x8],0x1
    mov    dword [ebp-0xc],0x0
.lzu_main:
    mov    eax,dword [ebp-0x8]
    lea    edx,[eax+0x1]
    mov    dword [ebp-0x8],edx
    mov    edx,dword [ebp+0x8]
    add    eax,edx
    movzx  eax,byte [eax]
    mov    byte [ebp-0xe],al
    movzx  eax,byte [ebp-0xe]
    cmp    al,byte [ebp-0xd]
    jne    .lzu_literal
    mov    edx,dword [ebp+0x8]
    mov    eax,dword [ebp-0x8]
    add    eax,edx
    movzx  eax,byte [eax]
    test   al,al
    jne    .lzu_compressed
    mov    eax,dword [ebp-0xc]
    lea    edx,[eax+0x1]
    mov    dword [ebp-0xc],edx
    mov    edx,dword [ebp+0xc]
    add    edx,eax
    movzx  eax,byte [ebp-0xd]
    mov    byte [edx],al
    add    dword [ebp-0x8],0x1
    jmp    .lzu_next
.lzu_compressed:
    mov    edx,dword [ebp+0x8]
    mov    eax,dword [ebp-0x8]
    add    eax,edx
    push   eax
    lea    eax,[ebp-0x14]
    push   eax
    call   _LZ_ReadVarSize
    add    esp,0x8
    add    dword [ebp-0x8],eax
    mov    edx,dword [ebp+0x8]
    mov    eax,dword [ebp-0x8]
    add    eax,edx
    push   eax
    lea    eax,[ebp-0x18]
    push   eax
    call   _LZ_ReadVarSize
    add    esp,0x8
    add    dword [ebp-0x8],eax
    mov    dword [ebp-0x4],0x0
    jmp    .lzu_copy_check
.lzu_copy:
    mov    eax,dword [ebp-0x18]
    mov    edx,dword [ebp-0xc]
    sub    edx,eax
    mov    eax,dword [ebp+0xc]
    add    eax,edx
    mov    ecx,dword [ebp+0xc]
    mov    edx,dword [ebp-0xc]
    add    edx,ecx
    movzx  eax,byte [eax]
    mov    byte [edx],al
    add    dword [ebp-0xc],0x1
    add    dword [ebp-0x4],0x1
.lzu_copy_check:
    mov    eax,dword [ebp-0x14]
    cmp    dword [ebp-0x4],eax
    jb     .lzu_copy
    jmp    .lzu_next
.lzu_literal:
    mov    eax,dword [ebp-0xc]
    lea    edx,[eax+0x1]
    mov    dword [ebp-0xc],edx
    mov    edx,dword [ebp+0xc]
    add    edx,eax
    movzx  eax,byte [ebp-0xe]
    mov    byte [edx],al
.lzu_next:
    mov    eax,dword [ebp-0x8]
    cmp    eax,dword [ebp+0x10]
    jb     .lzu_main
.lzu_end:
    leave
    ret
