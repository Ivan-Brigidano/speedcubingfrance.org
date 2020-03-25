import React, { Fragment, useState } from 'react';
import events from 'wca/events';
import { loadableComponent } from 'requests/loadable';
import { selfInfoUrl } from 'requests/routes';
import I18n from "i18n-for-js";

import EventList from './EventList';
import ResultsList from './ResultsList';

const ShowResult = loadableComponent(({
  competitionId,
  loadedState
}) => {
  const [activeId, setActive] = useState("333");
  const wcaEvent = events.byId[activeId];
  console.log(I18n.t("countries.XA"));
  console.log(I18n.currentLocale());
  return (
    <>
      <EventList activeId={activeId} onClick={setActive} />
      <h3 className="mt-3">
        {I18n.t("online_competitions.show_results.results", {event_name: wcaEvent.name})}
      </h3>
      <ResultsList id={{eventId: activeId, competitionId: competitionId}}
        canManageResults={loadedState && loadedState.can_manage_online_comps}
      />
    </>
  );
}, selfInfoUrl);

export default ShowResult;
