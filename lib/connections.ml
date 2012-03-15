(*
 * Copyright (c) 2012 Sebastian Probst Eide <sebastian.probst.eide@gmail.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Lwt
open Printf


type handle = 
  | Name of Sp.name
  | Wildcard

type address =
  | Address of Sp.addressable
  | NoAddress

type status =
  | IN_PROGRESS
  | OK
  | FAILED

type tactic_result =
  | Result of Rpc.tactic_name * status * (address * address) list 

type connection_state = {
  connections : (handle * handle, tactic_result list) Hashtbl.t;
}


let connection_db = {connections = (Hashtbl.create 0);}

let in_order a b = a < b

let get pair =
  try (Hashtbl.find connection_db.connections pair)
  with Not_found -> []

let set key value =
  Hashtbl.replace connection_db.connections key value

let update_for_tactic tactic_name status key value =
  let current_record = get key in
  let existed = ref false in
  let updated_records = List.map (function
    | Result(name, _status, _val) when name = tactic_name -> 
        existed := true;
        Result(tactic_name, status, value)
    | d -> d) current_record in
  let records_with_insertion = match !existed with
  | true -> updated_records
  | false -> Result(tactic_name, status, value) :: current_record in
  set key records_with_insertion

let flip_addresses addresses =
  List.map (fun (a,b) -> (b,a)) addresses

let name_to_db_name (a,b) =
  (Name(a), Name(b))

let ip_pair_list_to_address_list ips =
  let map_fn (a,b) = 
      Address(Sp.IPAddressInstance(a)), Address(Sp.IPAddressInstance(b)) in
  List.map map_fn ips

let get_address fn results = 
  let open List in
  let ok_results = fold_left (fun acc (Result(_name, status, addr_pair_list)) ->
    match status with
    | OK -> (map fn addr_pair_list) :: acc
    | _ -> acc
  ) [] results in
  flatten ok_results

let get_first_of_addresses results =
  get_address (fun (addr, _) -> addr) results

let get_second_of_addresses results =
  get_address (fun (_, addr) -> addr) results

let lookup a_name b_name =
  eprintf "Looking up connections from %s to %s\n%!" a_name b_name;
  let a = Name a_name in
  let b = Name b_name in
  let tunnels = match in_order a b with
  | true -> begin
      let tactic_result_list = get (a,b) in
      get_second_of_addresses tactic_result_list
  end
  | false -> begin
      let tactic_result_list = get (b,a) in
      get_first_of_addresses tactic_result_list
  end in
  let direct_connection = 
    let tactic_result_list = get (Wildcard, b) in
    get_second_of_addresses tactic_result_list in
  let connections = direct_connection @ tunnels in
  let filtered = List.filter (function
    | NoAddress -> false
    | _ -> true) connections in
  List.map (fun (Address(a)) -> a) filtered

(**********************************************************************
 * Public API *********************************************************)

let find a b =
  eprintf "Finding existing connections between %s and %s\n" a b;
  eprintf "Trying to establish new ones\n";
  Engine.connect a b;
  lookup a b

let store_addresses a b tactic_name status ip_pair_list =
  let (key, value) = match in_order a b with
    | true -> 
        let key = name_to_db_name (a,b) in
        let addr = ip_pair_list_to_address_list ip_pair_list in
        (key, addr)
    | false -> 
        let key = name_to_db_name (b,a) in
        let addr = flip_addresses 
            (ip_pair_list_to_address_list ip_pair_list) in
        (key, addr) in
  update_for_tactic tactic_name status key value

let set_public_ips a ips =
  eprintf "Storing ips for %s\n" a;
  List.iter (fun s -> eprintf "storing ip: %s\n%!" s) ips;
  let key = (Wildcard, Name(a)) in
  let addrs = List.map (fun ip -> (NoAddress, Address(Sp.IPAddressInstance(ip)))) ips in
  update_for_tactic "public_ips" OK key addrs
