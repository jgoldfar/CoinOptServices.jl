using JuMP

# type DummyNLPSolver <: MathProgBase.AbstractMathProgSolver
# end
# type DummyNLPModel <: MathProgBase.AbstractMathProgModel
# end
# MathProgBase.model(s::DummyNLPSolver) = DummyNLPModel()
# function MathProgBase.loadnonlinearproblem!(m::DummyNLPModel, numVar, numConstr, x_l, x_u, g_lb, g_ub, sense, d::MathProgBase.AbstractNLPEvaluator)
#     MathProgBase.initialize(d, [:ExprGraph])
#     println("objexpr = $(MathProgBase.obj_expr(d))")
#     println("isobjlinear(d,1) = $(MathProgBase.isobjlinear(d))")
#     println("isconstrlinear(d,1) = $(MathProgBase.isconstrlinear(d,1))")
#     println("isconstrlinear(d,2) = $(MathProgBase.isconstrlinear(d,2))")
#     println("isconstrlinear(d,3) = $(MathProgBase.isconstrlinear(d,3))")
#     println("constr_expr(d,1) = $(MathProgBase.constr_expr(d,1))")
#     println("constr_expr(d,2) = $(MathProgBase.constr_expr(d,2))")
#     println("constr_expr(d,3) = $(MathProgBase.constr_expr(d,3))")
# end
# #MathProgBase.setwarmstart!(m::DummyNLPModel,x) = nothing
# #MathProgBase.optimize!(m::DummyNLPModel) = nothing
# #MathProgBase.status(m::DummyNLPModel) = :Optimal
# #MathProgBase.getobjval(m::DummyNLPModel) = NaN
# #MathProgBase.getsolution(m::DummyNLPModel) = [1.0,1.0]
# MathProgBase.setvartype!(m::DummyNLPModel, vartype) = nothing

# JuMP version of bonminEx1_Nonlinear.osil
m = Model()
@defVar(m, 0 <= x0 <= 1, Bin)
@defVar(m, x1 >= 0)
@defVar(m, x2 >= 0)
@defVar(m, 0 <= x3 <= 5, Int)
@setObjective(m, Min, x0 - x1 - x2)
#@setNLObjective(m, Min, x1/x2)
@addNLConstraint(m, (x1 - 0.5)^2 + (x2 - 0.5)^2 <= 0.25)
@addConstraint(m, x0 - x1 <= 0)
@addConstraint(m, x1 + x2 + x3 <= 2)
@addNLConstraint(m, 1 <= log(x1/x2))


#A = JuMP.prepConstrMatrix(m)
#d = JuMP.JuMPNLPEvaluator(m, A)
d = JuMP.JuMPNLPEvaluator(m, JuMP.prepConstrMatrix(m))
MathProgBase.initialize(d, [:ExprGraph]);
MathProgBase.obj_expr(d)
MathProgBase.constr_expr(d, 1)
MathProgBase.constr_expr(d, 2)
MathProgBase.constr_expr(d, 3)
MathProgBase.constr_expr(d, 4)


using LightXML

xdoc = XMLDocument()

xroot = create_root(xdoc, "osil")
set_attribute(xroot, "xmlns", "os.optimizationservices.org")
set_attribute(xroot, "xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance")
set_attribute(xroot, "xsi:schemaLocation", "os.optimizationservices.org " *
    "http://www.optimizationservices.org/schemas/2.0/OSiL.xsd")

instanceHeader = new_child(xroot, "instanceHeader")
add_text(new_child(instanceHeader, "description"),
    "generated by OptimizationServices.jl on " *
    strftime("%Y/%m/%d at %H:%M:%S", time()))

instanceData = new_child(xroot, "instanceData")

variables = new_child(instanceData, "variables")
numVars  = d.m.numCols
varNames = d.m.colNames
varCat   = d.m.colCat
varLower = d.m.colLower
varUpper = d.m.colUpper
set_attribute(variables, "numberOfVariables", numVars)
for i = 1:numVars
    vari = new_child(variables, "var")
    # need to save these in an array for setvartype!
    set_attribute(vari, "name", varNames[i])
    set_attribute(vari, "type", jl2osil_vartypes[varCat[i]])
    set_attribute(vari, "lb", varLower[i]) # lb defaults to 0 if not specified!
    if isfinite(varUpper[i])
        set_attribute(vari, "ub", varUpper[i])
    end
end
numConstr = length(d.m.linconstr) + length(d.m.quadconstr) + length(d.m.nlpdata.nlconstr)

using OptimizationServices

# TODO: compare BitArray vs. Array{Bool} here
indicator = falses(numVars)
densevals = zeros(numVars)

objectives = new_child(instanceData, "objectives")
set_attribute(objectives, "numberOfObjectives", "1") # can MathProgBase do multi-objective problems?
obj = new_child(objectives, "obj")
set_attribute(obj, "maxOrMin", lowercase(string(d.m.objSense)))
# need to create an OsilMathProgModel type with state, set sense during loadnonlinearproblem!
# then implement MathProgBase.getsense for reading it
objexpr = MathProgBase.obj_expr(d)
nlobj = false
if MathProgBase.isobjlinear(d)
    @assertform objexpr.head :call
    objexprargs = objexpr.args
    @assertform objexprargs[1] :+
    constant = 0.0
    for i = 2:length(objexprargs)
        constant += addLinElem!(indicator, densevals, objexprargs[i])
    end
    if constant != 0.0
        set_attribute(obj, "constant", constant)
    end
    numberOfObjCoef = 0
    idx = findnext(indicator, 1)
    while idx != 0
        numberOfObjCoef += 1
        coef = new_child(obj, "coef")
        set_attribute(coef, "idx", idx - 1) # OSiL is 0-based
        add_text(coef, string(densevals[idx]))

        densevals[idx] = 0.0 # reset for later use in linear constraints
        idx = findnext(indicator, idx + 1)
    end
    fill!(indicator, false) # for Array{Bool}, set to false one element at a time?
    set_attribute(obj, "numberOfObjCoef", numberOfObjCoef)
else
    nlobj = true
    set_attribute(obj, "numberOfObjCoef", "0")
    # nonlinear objective goes in nonlinearExpressions, <nl idx="-1">
end

# create constraints section with bounds during loadnonlinearproblem!
# assume no constant attributes on constraints

# assume linear constraints are all at start
row = 1
nextrowlinear = MathProgBase.isconstrlinear(d, row)
if nextrowlinear
    # has at least 1 linear constraint
    linearConstraintCoefficients = new_child(instanceData, "linearConstraintCoefficients")
    numberOfValues = 0
    rowstarts = new_child(linearConstraintCoefficients, "start")
    add_text(new_child(rowstarts, "el"), "0")
    colIdx = new_child(linearConstraintCoefficients, "colIdx")
    values = new_child(linearConstraintCoefficients, "value")
end
while nextrowlinear
    constrexpr = MathProgBase.constr_expr(d, row)
    @assertform constrexpr.head :comparison
    #(lhs, rhs) = constr2bounds(constrexpr.args...)
    constrlinpart = constrexpr.args[end - 2]
    @assertform constrlinpart.head :call
    constrlinargs = constrlinpart.args
    @assertform constrlinargs[1] :+
    for i = 2:length(constrlinargs)
        addLinElem!(indicator, densevals, constrlinargs[i]) == 0.0 ||
            error("Unexpected constant term in linear constraint")
    end
    idx = findnext(indicator, 1)
    while idx != 0
        numberOfValues += 1
        add_text(new_child(colIdx, "el"), string(idx - 1)) # OSiL is 0-based
        add_text(new_child(values, "el"), string(densevals[idx]))

        densevals[idx] = 0.0 # reset for next row
        idx = findnext(indicator, idx + 1)
    end
    fill!(indicator, false) # for Array{Bool}, set to false one element at a time?
    add_text(new_child(rowstarts, "el"), string(numberOfValues))
    row += 1
    nextrowlinear = MathProgBase.isconstrlinear(d, row)
end
numLinConstr = row - 1
if numLinConstr > 0
    set_attribute(linearConstraintCoefficients, "numberOfValues", numberOfValues)
end

numberOfNonlinearExpressions = numConstr - numLinConstr + (nlobj ? 1 : 0)
if numberOfNonlinearExpressions > 0
    # has nonlinear objective or at least 1 nonlinear constraint
    nonlinearExpressions = new_child(instanceData, "nonlinearExpressions")
    set_attribute(nonlinearExpressions, "numberOfNonlinearExpressions",
        numberOfNonlinearExpressions)
    if nlobj
        nl = new_child(nonlinearExpressions, "nl")
        set_attribute(nl, "idx", "-1")
        expr2osnl!(nl, MathProgBase.obj_expr(d))
    end
    for row = numLinConstr + 1 : numConstr
        nl = new_child(nonlinearExpressions, "nl")
        set_attribute(nl, "idx", row - 1) # OSiL is 0-based
        constrexpr = MathProgBase.constr_expr(d, row)
        @assertform constrexpr.head :comparison
        #(lhs, rhs) = constr2bounds(constrexpr.args...)
        expr2osnl!(nl, constrexpr.args[end - 2])
    end
end



# writeproblem for nonlinear?


free(xdoc)

