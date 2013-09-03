module Fs_spec_extras = struct 

(* interactive:

    #require "sha";;

*)

open Fs_prelude
open Fs_spec

module Extra_ops = struct

  open Prelude
  open Fs_types1

(*
  let kind_of_inode ops s0 i0 = (
    if (ops.get_symlink i0) then S_LNK else S_REG)
*)

  let kind_of_inode_ref ops s0 i0_ref = (
      if (ops.get_symlink1 s0 i0_ref) then S_LNK else S_REG)

  let kind_of_entry ops s0 e = (
    match e with 
    | Inl _ -> S_DIR
    | Inr i0_ref -> (
      kind_of_inode_ref ops s0 i0_ref))

  let kind_of_path ops s0 p = (
    let rn = Resolve.process_path ops s0 p in
    match rn with
    | Dname2(_,_) -> S_DIR
    | Fname2(i0_ref,_) -> (kind_of_inode_ref ops s0 i0_ref)
    | _ -> (failwith ("kind_of_path, absent path: "^p)))

  let kind_of_name ops s0 d0_ref name = (
    let Some(e) = ops.resolve11 s0 d0_ref name in
    kind_of_entry ops s0 e)

  (* return a list of paths; p should point to a dir *)
  let ls_path ops s0 p = (
    let rn = Resolve.process_path ops s0 p in
    let Dname2(d0_ref,_) = rn in
    let ns = name_list_of_rname2 rn in
    let p = string_of_names ns.ns2 in
    let p = if p = "/" then "" else p in
    let Names1(es) = (ops.readdir1 s0 d0_ref).ret2 in
    let r = List.map (fun n -> p^"/"^n) es in
    r)

  let rec find_path ops s0 p = (
    let xs = ls_path ops s0 p in
    let ds = List.filter (fun p -> kind_of_path ops s0 p = S_DIR) xs in
    (* let xs = List.filter (fun p -> kind_of_path ops s0 p <> S_DIR) xs in *)
    let xs' = List.concat (List.map (find_path ops s0) ds) in
    xs@xs')

end


(* FIXME shouldn't this work with ops? *)
module File_utils2 = struct 

  open Unix

  type path = string list
  
  (* in this module, filenames (lists of strings) are absolute *)
  let string_of_longfname s = "/" ^ (String.concat "/" s)
  
  (* our operations on filesystems can be parameterized in terms of ls and readlink *)
  type 'a fs_ops = {
    ls4: 'a -> path -> path list;
    kind4: 'a -> path -> file_kind;
    readlink4: 'a -> path -> string;
    inode4: 'a -> path -> int
  }
 
  let is_dir ops s d = (ops.kind4 s d = S_DIR)
    
  let is_link ops s f = (ops.kind4 s f = S_LNK)

  let is_file ops s f = (ops.kind4 s f = S_REG)
      
  (* FIXME make tail recursive, alphabetical etc *)
  let rec find ops s d = 
    let ss = ops.ls4 s d in
    let ds = List.filter (is_dir ops s) ss in
    (List.concat (List.map (find ops s) ds))@ss (* order: want leaves first *)

end

(* FIXME shouldn't this work with ops? *)
module Unix_utils = struct

  open File_utils2
  
  let string_of_path = File_utils2.string_of_longfname
  let path_of_string s = Str.split (Str.regexp "/") s

  (* return a list of list of strings - a long filename is a list of dirs and a filename *)
  let ls d = (
    let lines = ref [] in
    let h = Unix.opendir (string_of_path d) in
    try
      while true; do
        lines := Unix.readdir h :: !lines
      done; []
    with End_of_file ->
      Unix.closedir h;
      let fs = List.map (fun s -> d@[s]) (List.filter (fun s -> not (s="." || s = "..")) (List.rev !lines)) in
      List.sort Pervasives.compare fs)
  let (_:string list -> string list list) = ls

  let kind f = (
    let open Unix.LargeFile in
    let stats = lstat (string_of_path f) in
    match stats.st_kind with 
    | Unix.S_DIR -> Unix.S_DIR
    | Unix.S_REG -> Unix.S_REG
    | Unix.S_LNK -> Unix.S_LNK
    | _ -> (failwith ("Unknown file type for file: "^(string_of_path f)))) 

  let inode f = (
    let open Unix.LargeFile in
    let stats = lstat (string_of_path f) in
    stats.st_ino)
  
  let readlink f = (
    let s = Unix.readlink (string_of_path f) in
    (* path_of_string *) s)

  let unix_ops = {
    ls4=(fun _ -> ls);
    kind4=(fun _ -> kind);
    readlink4=(fun _ -> readlink);
    inode4=(fun _ -> inode)
  }

  let is_file = File_utils2.is_file unix_ops ()
    
  let find = File_utils2.find unix_ops ()

end


(* interactive:

    #use "/tmp/l/general/research/parsing/src/p3_lib.toplevel.ml";;
    #use "/tmp/l/general/research/parsing/src/mycsv.toplevel.ml";;

*)

(* FIXME shouldn't this work with ops? *)
module Unix_dump_fs = struct

  open Unix
  open Unix_utils
  open Mycsv
  open Sha1
 
  let sha1_of_file fname = Sha1.to_hex (Sha1.file_fast fname)

  let sha1_of_string s = Sha1.to_hex (Sha1.string s)

  let records_of_path s = (
    let p = path_of_string s in
    let fs = find p in
    let f1 f = (
      let s = string_of_path f in
      let k = kind f in
      match k with 
      | S_REG -> [s;"F";(string_of_int (inode f));(sha1_of_file s)]
      | S_DIR -> [s;"D"]
      | S_LNK -> [s;"L";(readlink f)]
      | _ -> failwith "main")
    in
    let ss = List.map f1 fs in
    ss)

(*
  let fs = find ["tmp";"a"]
  let fs = List.filter is_file fs 
  let _ = List.map (fun f -> (string_of_path f,inode_of_file f, sha1_of_file (string_of_path f))) fs

  let _ = sha1_of_file "/mnt/sda7/tom/downloads/ubuntu/xubuntu-12.04.2-desktop-i386.iso"

  let fs = find ["tmp"]

  let _ = sha1_of_file "/tmp/a/tom.txt"
  let _ = sha1_of_file "/tmp/a/jen.txt"
*)

end

(*
module Dump_fs = struct

  open File_utils
  open Mycsv
  open Sha1
 
  let sha1_of_string s = Sha1.to_hex (Sha1.string s)

  let rec find ops s0 d = 
    let es = ops.get_entries s d in
    let ds = List.filter (is_dir ops s) ss in
    (List.concat (List.map (find ops s) ds))@ss (* order: want leaves first *)


  let records_of_path ops s0 s = (
    let p = path_of_string s in
    let fs = find p in
    let f1 f = (
      let s = string_of_path f in
      let k = kind f in
      match k with 
      | S_REG -> [s;"F";(string_of_int (inode f));(sha1_of_file s)]
      | S_DIR -> [s;"D"]
      | S_LNK -> [s;"L";(readlink f)]
      | _ -> failwith "main")
    in
    let ss = List.map f1 fs in
    ss)

(*
  let fs = find ["tmp";"a"]
  let fs = List.filter is_file fs 
  let _ = List.map (fun f -> (string_of_path f,inode_of_file f, sha1_of_file (string_of_path f))) fs

  let _ = sha1_of_file "/mnt/sda7/tom/downloads/ubuntu/xubuntu-12.04.2-desktop-i386.iso"

  let fs = find ["tmp"]

  let _ = sha1_of_file "/tmp/a/tom.txt"
  let _ = sha1_of_file "/tmp/a/jen.txt"
*)

end

*)


 end
;;
