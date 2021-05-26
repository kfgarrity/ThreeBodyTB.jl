

function myf(x)

    return 0.5 * x'*A*x

end

function mygrad(x)

    return 0.5 * x'*A*x, A*x

end
