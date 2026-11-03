#include <stdio.h>
#include <proto/exec.h>

int main(void)
{
    printf("hello from aros, ExecBase %p\n", (void *)SysBase);
    return 0;
}
