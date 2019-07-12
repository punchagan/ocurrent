type 'a or_error = ('a, [`Msg of string]) result

module type T = sig
  type t
  val equal : t -> t -> bool
  val pp : t Fmt.t
end

module type INPUT = sig
  type 'a t
  (** An input that was used while evaluating a term.
      If the input changes, the term should be re-evaluated. *)

  type job_id

  type watch

  type env
  (** A context which the caller can associate with an execution. *)

  val get : env -> 'a t -> 'a Output.t * job_id option * watch list
end

module type ANALYSIS = sig
  type 'a term
  (** See [TERM]. *)

  type t
  (** Information about the dependency graph of a term.
      This is useful to display the term's state as a diagram. *)

  type job_id

  val booting : t
  (** [booting] is a dummy analysis; useful while booting. *)

  val get : _ term -> t term

  val pp : t Fmt.t
  (** [pp] formats a [t] as a simple string. *)

  val pp_dot : t Fmt.t
  (** [pp_dot] formats a [t] as a graphviz dot graph. *)
end

module type TERM = sig
  type 'a input
  (** See [INPUT]. *)

  type +'a t
  (** An ['a t] is a term that produces a value of type ['a]. *)

  type description
  (** Information about operations hidden behind a bind. *)

  val pending : unit -> 'a t
  (** [pending ()] is a term that never produces a result. *)

  val return : 'a -> 'a t
  (** [return x] is a term that immediately succeeds with [x]. *)

  val fail : string -> 'a t
  (** [fail m] is a term that immediately fails with message [m]. *)

  val state : 'a t -> ('a, [`Pending | `Msg of string]) result t
  (** [state t] always immediately returns a successful result giving the current state of [t]. *)

  val catch : 'a t -> 'a or_error t
  (** [catch t] successfully returns [Ok x] if [t] evaluates successfully to [x],
      or successfully returns [Error e] if [t] fails with error [e].
      If [t] is pending then [catch t] will be pending too. *)

  val ignore_value : 'a t -> unit t
  (** [ignore_value x] is [map ignore x]. *)

  val of_output : 'a Output.t -> 'a t
  (** [of_output x] is a returned, failed or pending term. *)

  val map : ('a -> 'b) -> 'a t -> 'b t
  (** [map f x] is a term that runs [x] and then transforms the result using [f]. *)

  val pair : 'a t -> 'b t -> ('a * 'b) t
  (** [pair a b] is the pair containing the results of evaluating [a] and [b]
      (in parallel). *)

  val component : ('a, Format.formatter, unit, description) format4 -> 'a
  (** [component name] is used to annotate binds, so that the system can show a
      name for the operations hidden inside the bind's function. [name] is used
      as the label for the bind in the generated dot diagrams.
      For convenience, [name] can also be a format string. *)

  val bind : ?info:description -> ('a -> 'b t) -> 'a t -> 'b t
  (** [bind f x] is a term that first runs [x] to get [y] and then behaves as
      the term [f y]. Static analysis cannot look inside the [f] function until
      [x] is ready, so using [bind] makes static analysis less useful. You can
      use the [info] argument to provide some information here. *)

  val bind_input : info:description -> ('a -> 'b input) -> 'a t -> 'b t
  (** [bind_input ~info f x] is a term that first runs [x] to get [y] and then
      behaves as the input [f y]. [info] is used to describe the operation
      in the analysis result. *)

  val list_map : ('a t -> 'b t) -> 'a list t -> 'b list t
  (** [list_map f xs] adds [f] to the end of each input term
      and collects all the results into a single list. *)

  val list_iter : ('a t -> unit t) -> 'a list t -> unit t
  (** Like [list_map] but for the simpler case when the result is unit. *)

  val option_seq : 'a t option -> 'a option t
  (** [option_seq None] is [Current.return None] and
      [option_seq (Some x)] is [Current.map some x].
      This is useful for handling optional arguments that are currents. *)

  val all : unit t list -> unit t
  (** [all xs] is a term that succeeds if every term in [xs] succeeds. *)

  val gate : on:unit t -> 'a t -> 'a t
  (** [gate ~on:ctrl x] is the same as [x], once [ctrl] succeeds. *)

  module Syntax : sig
    val (let+) : 'a t -> ('a -> 'b) -> 'b t
    (** Syntax for [map]. Use this to process the result of a term without
        using any special effects. *)

    val (and+) : 'a t -> 'b t -> ('a * 'b) t
    (** Syntax for [pair]. Use this to depend on multiple terms. *)

    val (let*) : 'a t -> ('a -> 'b t) -> 'b t
    (** Monadic [bind]. Use this if the next part of your pipeline can only
        be determined at runtime by looking at the concrete value. Static
        analysis cannot predict what this will do until the input is ready. *)

    val (let>) : 'a t -> ('a -> 'b input) -> description -> 'b t
    (** [let>] is used to define a component.
        e.g. [component "my-op" |>
              let> x = fetch uri in
              ...] *)

    val (let**) : 'a t -> ('a -> 'b t) -> description -> 'b t
    (** Like [let*], but allows you to name the operation.
        e.g. [component "my-op" |> let** x = fetch uri in ...] *)

    val (and>) : 'a t -> 'b t -> ('a * 'b) t
    (** Syntax for [pair]. Use this to depend on multiple terms.
        Note: this is the same as [and+]. *)

    val (and*) : 'a t -> 'b t -> ('a * 'b) t
    (** Syntax for [pair]. Use this to depend on multiple terms.
        Note: this is the same as [and+]. *)
  end
end

module type EXECUTOR = sig
  type 'a term
  (** See [TERM]. *)

  type watch
  (** See [INPUT]. *)

  type env
  (** See [INPUT]. *)

  type analysis
  (** See [ANALYSIS]. *)

  val run : env:env -> (unit -> 'a term) -> 'a Output.t * analysis * watch list
  (** [run ~env f] evaluates term [f ()], returning the current output, its analysis,
      and the set of inputs that were used during the evaluation. If any of the
      inputs change, you should call [run] again to get the new results. *)
end
