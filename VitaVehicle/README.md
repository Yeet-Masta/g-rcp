# Why?

No bad feelings, but i'm just noting what i found to ensure that i can learn from it.

- There are so many places in which Jreo decided to use if: elif: instead of clamp(). Let's clean that up.
- Sometimes he uses 10000000000000000000000000000000000.0 instead of INF. However that seems intentional in certain places. In comparisons, INF is not considered a number, causing an error. I wish it was like Math.HUGE.
- There are so many ambiguous and short variable names that just make the code unreadable.
- steer2 - The physical steer of the wheels.
- He also toggles things with if else instead of just doing `toggle = !toggle`.
- Does `if a != b: a = b` instead of just `a = b`.
- Doesn't use remap(), uses `-x + 2x` instead.
	- These are equivalent: `(front_load/total)*0.5 +0.5` and `remap(front_load/total, -1.0, 1.0, 0.0, 1.0)`
- Multiplies by 60 to convert to time per second, instead of dividing by delta.
- Does `(a/b)*(a/b)` instead of `pow(a/b, 2)`. That one is more like personal preference.
- Uses some weird `a*float(b>0.0) -a*float(b<0.0)` which simplifies to `a*sign(b)`.
- Uses _process and _physics_process for one-time things that can be done in _ready.
- Doesn't use guard clauses.
- Limits the digits after a decimal with `int(a*10)/10` instead of ``

So my questions:
- Why aren't we simplifying code to make it more readable? - It works for him, but not for me.
- Why are we using magic numbers everywhere?

# Bugs

Test these cases to ensure stability:
	- What happens if the car is free-falling? What if you change car to kill any sideways momentum and fall dead down?
	- How does the car sound when skidding on/off the road? Is the sound infinitely loud?

# Notes

Lines of code:
	- First measured 4627 lines in 42 scripts
	- After some cleanup i got 4407 lines in 42 scripts
