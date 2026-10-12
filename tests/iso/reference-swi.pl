% Ground-truth observations from SWI-Prolog on the same conventional
% Prolog source programs. Only the oracle runs on this runtime.
:- use_module(library(http/json)).
:- use_module(library(readutil)).
:- use_module(library(solution_sequences)).
:- use_module(library(time)).
:- initialization(main, main).

oracle_exception_class(error(Descriptor, _), Name) :-
    !,
    ( compound(Descriptor) ->
        functor(Descriptor, Class, _)
    ; Class = Descriptor
    ),
    atom_string(Class, Name).
oracle_exception_class(Ball, Name) :-
    ( atom(Ball) ->
        atom_string(Ball, Name)
    ; compound(Ball) ->
        functor(Ball, Functor, _),
        atom_string(Functor, Name)
    ; Name = "unknown_exception"
    ).

% Results are normalized as typed, operator-independent term trees.
% In SWI-Prolog >= 7, a list pair's native functor may be '[|]' rather
% than '.', hence the explicit nonempty list pattern.
oracle_term(Term, Dict) :-
    ( nonvar(Term), Term = '$VAR'(Index), integer(Index) ->
        Dict = _{var:Index}
    ; var(Term) ->
        throw(error(instantiation_error, oracle_term/2))
    ; integer(Term) ->
        number_string(Term, Text),
        Dict = _{integer:Text}
    ; Term == [] ->
        % SWI 7+ represents [] as a special constant rather than an ISO atom.
        % Normalize the representation, but keep SWI's predicate behavior intact.
        Dict = _{atom:"[]"}
    ; atom(Term) ->
        atom_string(Term, Text),
        Dict = _{atom:Text}
    ; nonvar(Term), Term = [Head|Tail] ->
        oracle_term(Head, HeadTree),
        oracle_term(Tail, TailTree),
        Dict = _{functor:".", args:[HeadTree,TailTree]}
    ; compound(Term) ->
        compound_name_arguments(Term, Functor, Args),
        atom_string(Functor, Name),
        maplist(oracle_term, Args, Trees),
        Dict = _{functor:Name, args:Trees}
    ; throw(error(type_error(iso_term, Term), oracle_term/2))
    ).

oracle_pair(Name=Value, Name-JSON) :-
    % Dict keys must be atoms; read_term's variable_names/1 supplies atoms.
    oracle_term(Value, JSON).

oracle_answer(Variables, Dict) :-
    % numbervars is per answer, preserving aliasing of its unbound variables.
    numbervars(Variables, 0, _),
    maplist(oracle_pair, Variables, Pairs),
    dict_pairs(Dict, bindings, Pairs).

oracle_run(GoalText, Limit, Result) :-
    read_term_from_atom(GoalText, Goal,
                        [variable_names(Variables), syntax_errors(error)]),
    % Put the watchdog around *the complete search*. Wrapping each Goal
    % invocation with call_with_time_limit/2 can discard alternatives.
    ProbeLimit is Limit + 1,
    call_with_time_limit(5,
        findnsols(ProbeLimit, Variables, call(Goal), AllAnswers)),
    length(AllAnswers, Observed),
    ( Observed > Limit ->
        length(Answers, Limit),
        append(Answers, _, AllAnswers),
        Truncated = true
    ; Answers = AllAnswers,
      Truncated = false
    ),
    maplist(oracle_answer, Answers, Solutions),
    Result = _{status:"ok", solutions:Solutions, truncated:Truncated}.

oracle_observation(Id, GoalText, Limit, Result) :-
    catch(oracle_run(GoalText, Limit, Body), Error,
          ( oracle_exception_class(Error, Class),
            Body = _{status:"exception",exception:Class} )),
    Result = Body.put(id, Id).

oracle_line(Line, Output) :-
    ( Line = "" ->
        true
    ; sub_string(Line, 0, 1, _, "#") ->
        true
    ; split_string(Line, "\t", "", [Id, GoalText, CountText, _Baseline]) ->
        number_string(Limit, CountText),
        ( Limit > 0, Limit < 1000 ->
            oracle_observation(Id, GoalText, Limit, Result),
            json_write_dict(Output, Result, [width(0)]),
            nl(Output)
        ; throw(error(domain_error(solution_limit, Limit), oracle_line/2))
        )
    ; throw(error(syntax_error(malformed_reference_case(Line)), oracle_line/2))
    ).

oracle_lines(Input, Output) :-
    read_line_to_string(Input, Line),
    ( Line == end_of_file ->
        true
    ; oracle_line(Line, Output),
      oracle_lines(Input, Output)
    ).

main :-
    current_prolog_flag(argv, [CasesFile, OutputFile|Programs]),
    Programs \= [],
    maplist(consult, Programs),
    setup_call_cleanup(
        open(CasesFile, read, Cases, [encoding(utf8)]),
        setup_call_cleanup(
            open(OutputFile, write, Output, [encoding(utf8)]),
            oracle_lines(Cases, Output),
            close(Output)),
        close(Cases)).
