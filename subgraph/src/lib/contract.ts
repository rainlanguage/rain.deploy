// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import { Contract } from "../../generated/schema";

// `graph codegen` renders an enum field as a plain `string`, so the schema's `ContractKind` values live here.
export namespace ContractKind {
  export const CONFIG_REGISTRY = "CONFIG_REGISTRY";
  export const MIGRATION_REGISTRY = "MIGRATION_REGISTRY";
  export const CONFIG_REGISTRY_V5 = "CONFIG_REGISTRY_V5";
  export const MIGRATION_REGISTRY_V5 = "MIGRATION_REGISTRY_V5";
}

export function getOrCreateContract(
  address: Bytes,
  kind: string,
  block: BigInt,
): Contract {
  let existing = Contract.load(address);
  if (existing !== null) {
    return existing;
  }
  let contract = new Contract(address);
  contract.kind = kind;
  contract.firstIndexedBlock = block;
  contract.save();
  return contract;
}
