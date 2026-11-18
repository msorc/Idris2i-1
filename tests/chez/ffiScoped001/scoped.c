// Call `f` on 1 to `n` and add up the results: `f` is only used during the
// call, as with qsort.
int sumWith(int (*f)(int), int n) {
    int sum = 0;
    for (int i = 1; i <= n; i++)
        sum += f(i);
    return sum;
}
