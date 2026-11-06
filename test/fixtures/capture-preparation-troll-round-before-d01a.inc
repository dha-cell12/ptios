static int SCRoundUp(int value, int multiple)
{
    if (multiple <= 0) return value;
    int rem = value % multiple;
    return rem == 0 ? value : value + multiple - rem;
}

