double f(double a, int n)
{
    union { double dbl; } p;

    p.dbl = a;
    while (n-- > 0)
        p.dbl *= 10.0;
    return p.dbl;
}
