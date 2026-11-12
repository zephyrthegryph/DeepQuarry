import type { BooleanLike } from 'tgui-core/react';

export type Access = {
  name: string;
  id: number;
  region: number;
  access_type: number;
  has_req: BooleanLike;
  has_req_one: BooleanLike;
};
