# Compiling / Python

## Compiling

Julia normally makes heavy use of just-in-time (jit) compilation to
compile efficient versions of functions for any given input types. This
has a side effect that the second time you run a given function with
certain variable types is much faster than the first time, because the
efficient compiled machine code is cached.

It is possible to store a system image file that contains precompiled
versions of functions from a Julia package, using the
[PackageCompiler](https://github.com/JuliaLang/PackageCompiler.jl)
package. This will greatly reduce the time to load and run the first
instance of precompiled functions.

To help automate this process, you can use the compile() function. It is
recommended that you precompile Plots at the same time.

```
using ThreeBodyTB; using Plots; ThreeBodyTB.compile()
```

This will run the examples in order to precompile the appropriate
functions, and then create a file called sys_threebodytb.so in
~/.julia/sysimages/. To load the sysimage, run Julia as 

julia --sysimage ~/.julia/sysimages/sys_threebodytb.so

Note that the compilation takes several minutes and significant disk space.

## Python

While running ThreeBodyTB using Julia is the easiest option, I
understand that many users have existing codes in
Python. Therefore, I have created a separate github package in python,
[ThreeBodyTB_python](https://github.com/kfgarrity/ThreeBodyTB_python),
that hosts a wrapper that allows the user to call my Julia functions
like they were in python.

This works by using the [PyJulia](https://github.com/JuliaPy/pyjulia)
interface. The wrapper will, if necessary, a) download & install Julia b)
download & install ThreeBodyTB.jl, and c) create a system image for
fast loading in python.
